module Ahoy::Visit::Pages
  extend ActiveSupport::Concern

  class_methods do
    def imported_pages_aggregates(_range)
      {}
    end

    def imported_entry_aggregates(_range)
      {}
    end

    def imported_exit_aggregates(_range)
      {}
    end

    def pages_payload(query, limit: nil, page: nil, search: nil, order_by: nil)
      mode = query[:mode] || "pages"
      filters = query[:filters] || {}
      comparison_names = Ahoy::Visit.comparison_names_filter(query)
      range, = Ahoy::Visit.range_and_interval_for(query[:period], nil, query)
      adv = query[:advanced_filters] || []
      visits = Ahoy::Visit.scoped_visits(range, filters, advanced_filters: adv)
      goal = filters["goal"].presence

      column = :landing_page

      if limit && page
        pattern = search.present? ? Ahoy::Visit.like_contains(search) : nil

        if mode == "pages"
          events = Ahoy::Visit.scoped_events(range, filters, advanced_filters: adv)
          expr = "COALESCE(NULLIF(split_part(ahoy_events.properties->>'page', CHR(63), 1), ''), '(unknown)')"
          rel = events
          if pattern.present?
            search_clause = "LOWER(COALESCE(NULLIF(split_part(ahoy_events.properties->>'page', CHR(63), 1), ''), '(unknown)')) LIKE ?"
            rel = rel.where(search_clause, pattern)
          end
          grouped_visit_ids = rel.group(Arel.sql(expr)).pluck(Arel.sql("#{expr}, ARRAY_AGG(DISTINCT ahoy_events.visit_id)")).to_h
          counts = Ahoy::Visit.unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits)
          pageviews_by_page = events.group(Arel.sql(expr)).count
          filter_page_groups!(grouped_visit_ids, counts, comparison_names, pageviews_by_page)
          total = Ahoy::Visit.percentage_total_visitors(visits)

          sorted_names = begin
            if order_by
              metric, _ = order_by
              case metric
              when "percentage"
                Ahoy::Visit.order_names(
                  counts: counts,
                  metrics_map: counts.keys.index_with { |n| { percentage: (counts[n].to_f / total) } },
                  order_by: order_by
                )
              when "pageviews"
                Ahoy::Visit.order_names(counts: pageviews_by_page, metrics_map: {}, order_by: order_by)
              when "bounce_rate", "visit_duration"
                metrics_all = Ahoy::Visit.calculate_group_metrics(grouped_visit_ids, range, filters)
                Ahoy::Visit.order_names(counts: counts, metrics_map: counts.keys.index_with { |n| metrics_all[n] || {} }, order_by: order_by)
              when "time_on_page", "scroll_depth"
                # Leave complex TOP/scroll sorts behavior as-is by computing the required maps
                top_metrics_all = compute_time_on_page_and_scroll(range, filters, grouped_visit_ids)
                Ahoy::Visit.order_names(counts: counts, metrics_map: counts.keys.index_with { |n| top_metrics_all[n] || {} }, order_by: order_by)
              else
                Ahoy::Visit.order_names(counts: counts, metrics_map: {}, order_by: order_by)
              end
            else
              Ahoy::Visit.order_names(counts: counts, metrics_map: {}, order_by: nil)
            end
          end

          if goal.present?
            denominator_counts = goal_denominator_counts_for_pages(query, mode: mode, search: search)
            conversions, cr = Ahoy::Visit.conversions_and_rates(grouped_visit_ids, visits, range, filters, goal, advanced_filters: adv, denominator_counts: denominator_counts)
            sorted_names = Ahoy::Visit.order_names_with_conversions(conversions: conversions, cr: cr, order_by: order_by)

            paged_names, has_more = Ahoy::Visit.paginate_names(sorted_names, limit: limit, page: page)

            results = paged_names.map do |name|
              label = name.to_s.presence || "(none)"
              {
                name: label,
                visitors: conversions[name] || 0,
                conversion_rate: Ahoy::Visit.goal_conversion_rate(conversions[name] || 0, denominator_counts[label])
              }
            end

            {
              results: results,
              metrics: %i[visitors conversion_rate],
              meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query), metric_labels: { visitors: "Conversions", conversionRate: "Conversion Rate" } }
            }
          else
            paged_names, has_more = Ahoy::Visit.paginate_names(sorted_names, limit: limit, page: page)

            page_visit_ids = grouped_visit_ids.slice(*paged_names)
            entry_map = Ahoy::Visit.entry_page_label_by_visit(visits, page_visit_ids)
            restricted = Ahoy::Visit.restrict_visits_to_entry_page(page_visit_ids, entry_map)
            group_metrics = Ahoy::Visit.calculate_group_metrics(restricted, range, filters)
            tops = compute_time_on_page_and_scroll(range, filters, page_visit_ids)

            results = paged_names.map do |name|
              v = counts[name]
              {
                name: name.to_s.presence || "(none)",
                visitors: v,
                percentage: (v.to_f / total).round(3),
                pageviews: pageviews_by_page[name] || 0,
                bounce_rate: group_metrics.dig(name, :bounce_rate),
                visit_duration: group_metrics.dig(name, :visit_duration),
                time_on_page: tops.dig(name, :time_on_page),
                scroll_depth: tops.dig(name, :scroll_depth)
              }
            end

            if query[:with_imported]
              imp = Ahoy::Visit.imported_pages_aggregates(range)
              results.each do |row|
                if (h = imp[row[:name]])
                  row[:visitors] = row[:visitors].to_i + h[:visitors].to_i
                  row[:pageviews] = row[:pageviews].to_i + h[:pageviews].to_i
                end
              end
            end

            { results: results, metrics: %i[visitors percentage pageviews bounce_rate time_on_page scroll_depth], meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query), metric_labels: { percentage: "Percentage" } } }
          end
        elsif mode == "entry"
          base = visits
          present_scope = base.where.not(landing_page: nil).where.not(landing_page: "")
          raw_groups = present_scope.group(:landing_page).pluck(:landing_page, Arel.sql("ARRAY_AGG(ahoy_visits.id)"))
          norm_groups = Hash.new { |h, k| h[k] = [] }
          needs_derivation_ids = []
          raw_groups.each do |lp, ids|
            label = normalized_path_only(lp)
            label = "(unknown)" if label.blank?
            if internal_entry_label?(label)
              needs_derivation_ids.concat(Array(ids))
            else
              norm_groups[label] += ids
            end
          end
          missing_ids = base.where("landing_page IS NULL OR landing_page = ''").pluck(:id)
          missing_ids.concat(needs_derivation_ids)
          if missing_ids.any?
            ev_rows = Ahoy::Event
              .where(name: "pageview", visit_id: missing_ids, time: range)
              .pluck(Arel.sql("visit_id, time, COALESCE(NULLIF(split_part(ahoy_events.properties->>'page', '?', 1), ''), '(unknown)')"))
            first_page_by_visit = {}
            ev_rows.each do |vid, t, pg|
              prev = first_page_by_visit[vid]
              t_val = t.respond_to?(:to_time) ? t.to_time : t
              if prev.nil? || t_val < prev[0]
                first_page_by_visit[vid] = [ t_val, pg.to_s ]
              end
            end
            first_page_by_visit.each do |vid, (_t, pg)|
              label = normalized_path_only(pg)
              label = "(unknown)" if label.blank?
              next if internal_entry_label?(label)
              norm_groups[label] << vid
            end
          end
          if pattern.present?
            norm_groups.select! { |k, _| k.downcase.include?(search.downcase) }
          end
          grouped_visit_ids = norm_groups
          entrances_by_page = grouped_visit_ids.transform_values(&:size)

          all_visit_ids = grouped_visit_ids.values.flatten
          visitors_by_visit = visits.where(id: all_visit_ids).pluck(:id, :visitor_token).to_h
          unique_visitors_by_page = {}
          grouped_visit_ids.each do |name, ids|
            tokens = ids.filter_map { |vid| visitors_by_visit[vid] }.uniq
            unique_visitors_by_page[name] = tokens.size
          end
          filter_page_groups!(grouped_visit_ids, unique_visitors_by_page, comparison_names, entrances_by_page)
          total = Ahoy::Visit.percentage_total_visitors(visits)

          if goal.present?
            denominator_counts = goal_denominator_counts_for_pages(query, mode: mode, search: search)
            conversions, cr = Ahoy::Visit.conversions_and_rates(grouped_visit_ids, visits, range, filters, goal, advanced_filters: adv, denominator_counts: denominator_counts)
            sorted_names = Ahoy::Visit.order_names_with_conversions(conversions: conversions, cr: cr, order_by: order_by)

            paged_names, has_more = Ahoy::Visit.paginate_names(sorted_names, limit: limit, page: page)

            results = paged_names.map do |name|
              label = name.to_s.presence || "(none)"
              {
                name: label,
                visitors: conversions[name] || 0,
                conversion_rate: Ahoy::Visit.goal_conversion_rate(conversions[name] || 0, denominator_counts[label])
              }
            end

            {
              results: results,
              metrics: %i[visitors conversion_rate],
              meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query), metric_labels: { visitors: "Conversions", conversionRate: "Conversion Rate" } }
            }
          else
            sorted_names = begin
              if order_by
                metric, _ = order_by
                case metric
                when "percentage"
                  Ahoy::Visit.order_names(
                    counts: unique_visitors_by_page,
                    metrics_map: unique_visitors_by_page.keys.index_with { |n| { percentage: (unique_visitors_by_page[n].to_f / total) } },
                    order_by: order_by
                  )
                when "visits"
                  Ahoy::Visit.order_names(counts: entrances_by_page, metrics_map: {}, order_by: order_by)
                when "bounce_rate", "visit_duration"
                  metrics_all = Ahoy::Visit.calculate_group_metrics(grouped_visit_ids, range, filters)
                  Ahoy::Visit.order_names(counts: unique_visitors_by_page, metrics_map: unique_visitors_by_page.keys.index_with { |n| metrics_all[n] || {} }, order_by: order_by)
                else
                  Ahoy::Visit.order_names(counts: unique_visitors_by_page, metrics_map: {}, order_by: order_by)
                end
              else
                Ahoy::Visit.order_names(counts: unique_visitors_by_page, metrics_map: {}, order_by: nil)
              end
            end

            paged_names, has_more = Ahoy::Visit.paginate_names(sorted_names, limit: limit, page: page)

            page_visit_ids = grouped_visit_ids.slice(*paged_names)
            group_metrics = Ahoy::Visit.calculate_group_metrics(page_visit_ids, range, filters)

            results = paged_names.map do |name|
              {
                name: name.to_s.presence || "(none)",
                visitors: unique_visitors_by_page[name] || 0,
                percentage: ((unique_visitors_by_page[name] || 0).to_f / total).round(3),
                visits: entrances_by_page[name] || 0,
                bounce_rate: group_metrics.dig(name, :bounce_rate),
                visit_duration: group_metrics.dig(name, :visit_duration)
              }
            end

            if query[:with_imported]
              imp = Ahoy::Visit.imported_entry_aggregates(range)
              results.each do |row|
                if (h = imp[row[:name]])
                  row[:visitors] = row[:visitors].to_i + h[:visitors].to_i
                  row[:visits] = row[:visits].to_i + h[:entrances].to_i
                end
              end
            end

            {
              results: results,
              metrics: %i[visitors percentage visits bounce_rate visit_duration],
              meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query), metric_labels: { visits: "Total Entrances", percentage: "Percentage" } }
            }
          end
        else
          pattern = search.present? ? Ahoy::Visit.like_contains(search) : nil
          events = Ahoy::Visit.scoped_events(range, filters, advanced_filters: adv)
          expr = "COALESCE(NULLIF(split_part(ahoy_events.properties->>'page', '?', 1), ''), '(unknown)')"

          ev_rows = events.pluck(Arel.sql("visit_id, time, #{expr}"))
          last_page_by_visit = {}
          ev_rows.each do |vid, t, page_name|
            prev = last_page_by_visit[vid]
            t_val = t.respond_to?(:to_time) ? t.to_time : t
            prev_time = prev ? (prev.is_a?(Array) ? prev[0] : prev.first) : nil
            if prev.nil? || t_val > prev_time
              last_page_by_visit[vid] = [ t_val, page_name ]
            end
          end

          exit_groups = Hash.new { |h, k| h[k] = [] }
          last_page_by_visit.each do |vid, (_t, page_name)|
            label = page_name.to_s
            label = "(unknown)" if label.strip.empty?
            exit_groups[label] << vid
          end

          if pattern.present?
            exit_groups.select! { |name, _| name.downcase.include?(search.downcase) }
          end

          exits_by_page = exit_groups.transform_values { |ids| ids.size }

          all_exit_visit_ids = exit_groups.values.flatten
          visitors_by_visit = visits.where(id: all_exit_visit_ids).pluck(:id, :visitor_token).to_h
          unique_visitors_by_page = {}
          exit_groups.each do |name, ids|
            tokens = ids.filter_map { |vid| visitors_by_visit[vid] }.uniq
            unique_visitors_by_page[name] = tokens.size
          end
          filter_page_groups!(exit_groups, unique_visitors_by_page, comparison_names, exits_by_page)
          total = Ahoy::Visit.percentage_total_visitors(visits)

          pageviews_by_page = events.group(Arel.sql(expr)).count
          exit_rate_by_page = {}
          exits_by_page.each do |name, exits|
            pv = pageviews_by_page[name] || 0
            exit_rate_by_page[name] = pv > 0 ? (exits.to_f / pv.to_f * 100.0).round(2) : 0.0
          end
          exit_rate_by_page.select! { |name, _| comparison_names.include?(formatted_page_name(name)) } if comparison_names.any?

          if goal.present?
            grouped_visit_ids = exit_groups
            denominator_counts = goal_denominator_counts_for_pages(query, mode: mode, search: search)
            conversions, cr = Ahoy::Visit.conversions_and_rates(grouped_visit_ids, visits, range, filters, goal, advanced_filters: adv, denominator_counts: denominator_counts)
            sorted_names = Ahoy::Visit.order_names_with_conversions(conversions: conversions, cr: cr, order_by: order_by)

            paged_names, has_more = Ahoy::Visit.paginate_names(sorted_names, limit: limit, page: page)

            results = paged_names.map do |name|
              label = name.to_s.presence || "(none)"
              { name: label, visitors: conversions[name] || 0, conversion_rate: Ahoy::Visit.goal_conversion_rate(conversions[name] || 0, denominator_counts[label]) }
            end

            { results: results, metrics: %i[visitors conversion_rate], meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query), metric_labels: { visitors: "Conversions", conversionRate: "Conversion Rate" } } }
          else
            sorted_names = begin
              if order_by
                metric, _ = order_by
                case metric
                when "percentage"
                  Ahoy::Visit.order_names(
                    counts: unique_visitors_by_page,
                    metrics_map: unique_visitors_by_page.keys.index_with { |n| { percentage: (unique_visitors_by_page[n].to_f / total) } },
                    order_by: order_by
                  )
                when "visits"
                  Ahoy::Visit.order_names(counts: exits_by_page, metrics_map: {}, order_by: order_by)
                when "exit_rate"
                  map = exit_rate_by_page.transform_values { |v| { exit_rate: v } }
                  Ahoy::Visit.order_names(counts: unique_visitors_by_page, metrics_map: map, order_by: order_by)
                else
                  Ahoy::Visit.order_names(counts: unique_visitors_by_page, metrics_map: {}, order_by: order_by)
                end
              else
                Ahoy::Visit.order_names(counts: unique_visitors_by_page, metrics_map: {}, order_by: nil)
              end
            end

            paged_names, has_more = Ahoy::Visit.paginate_names(sorted_names, limit: limit, page: page)

            results = paged_names.map do |name|
              {
                name: name.to_s.presence || "(none)",
                visitors: unique_visitors_by_page[name] || 0,
                percentage: ((unique_visitors_by_page[name] || 0).to_f / total).round(3),
                visits: exits_by_page[name] || 0,
                exit_rate: exit_rate_by_page[name] || 0.0
              }
            end

            if query[:with_imported]
              imp = Ahoy::Visit.imported_exit_aggregates(range)
              results.each do |row|
                if (h = imp[row[:name]])
                  total_exits = row[:visits].to_i + h[:exits].to_i
                  total_pageviews = (pageviews_by_page[row[:name]] || 0) + h[:pageviews].to_i
                  row[:visitors] = row[:visitors].to_i + h[:visitors].to_i
                  row[:visits] = total_exits
                  row[:exit_rate] = total_pageviews.positive? ? (total_exits.to_f / total_pageviews.to_f * 100.0).round(2) : row[:exit_rate]
                end
              end
            end

            { results: results, metrics: %i[visitors percentage visits exit_rate], meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query), metric_labels: { visits: "Total Exits", exitRate: "Exit Rate", percentage: "Percentage" } } }
          end
        end
      else
        if mode == "pages"
          events = Ahoy::Visit.scoped_events(range, filters, advanced_filters: adv)
          expr = "COALESCE(NULLIF(split_part(ahoy_events.properties->>'page', '?', 1), ''), '(unknown)')"
          counts = events.group(Arel.sql(expr)).distinct.count(:visitor_token)
          if counts.empty?
            raw = visits.where.not(landing_page: nil).group(:landing_page).distinct.count(:visitor_token)
            counts = Hash.new(0)
            raw.each do |lp, n|
              label = normalized_path_and_query(lp)
              label = "(unknown)" if label.blank?
              next if internal_entry_label?(label)
              counts[label] += n
            end
          end
          if query[:with_imported]
            imported = Ahoy::Visit.imported_pages_aggregates(range)
            imported.each do |name, h|
              counts[name] = counts[name].to_i + h[:visitors].to_i
            end
          end
          total = Ahoy::Visit.percentage_total_visitors(visits)
          rows = counts.sort_by { |_, v| -v }.map { |(name, v)| { name: name.to_s.presence || "(none)", visitors: v, percentage: (v.to_f / total).round(3) } }
          { results: rows, metrics: %i[visitors percentage], meta: { has_more: false, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query), metric_labels: { percentage: "Percentage" } } }
        elsif mode == "entry"
          counts = Hash.new(0)
          present_scope = visits.where.not(landing_page: nil).where.not(landing_page: "")
          present = present_scope.group(:landing_page).distinct.count(:visitor_token)
          needs_derivation_ids = []
          present_scope.group(:landing_page).pluck(:landing_page, Arel.sql("ARRAY_AGG(ahoy_visits.id)")).each do |lp, ids|
            label = normalized_path_only(lp)
            label = "(unknown)" if label.blank?
            if internal_entry_label?(label)
              needs_derivation_ids.concat(Array(ids))
            end
          end
          present.each do |lp, n|
            label = normalized_path_only(lp)
            label = "(unknown)" if label.blank?
            next if internal_entry_label?(label)
            counts[label] += n
          end
          missing_ids = visits.where("landing_page IS NULL OR landing_page = ''").pluck(:id)
          missing_ids.concat(needs_derivation_ids)
          if missing_ids.any?
            ev_rows = Ahoy::Event
              .where(name: "pageview", visit_id: missing_ids, time: range)
              .pluck(Arel.sql("visit_id, time, COALESCE(ahoy_events.properties->>'page', '(unknown)')"))
            first_page_by_visit = {}
            ev_rows.each do |vid, t, pg|
              prev = first_page_by_visit[vid]
              t_val = t.respond_to?(:to_time) ? t.to_time : t
              if prev.nil? || t_val < prev[0]
                first_page_by_visit[vid] = [ t_val, pg.to_s ]
              end
            end
            visitors_by_visit = visits.where(id: first_page_by_visit.keys).pluck(:id, :visitor_token).to_h
            per_label_visitors = Hash.new { |h, k| h[k] = Set.new }
            first_page_by_visit.each do |vid, (_t, pg)|
              label = normalized_path_only(pg)
              label = "(unknown)" if label.blank?
              next if internal_entry_label?(label)
              tok = visitors_by_visit[vid]
              per_label_visitors[label] << tok if tok.present?
            end
            per_label_visitors.each { |label, set| counts[label] += set.size }
          end
          if query[:with_imported]
            imported = Ahoy::Visit.imported_entry_aggregates(range)
            imported.each do |name, h|
              counts[name] = counts[name].to_i + h[:visitors].to_i
            end
          end
          total = Ahoy::Visit.percentage_total_visitors(visits)
          rows = counts.sort_by { |_, v| -v }.map { |(name, v)| { name: name.to_s.presence || "(none)", visitors: v, percentage: (v.to_f / total).round(3) } }
          { results: rows, metrics: %i[visitors percentage], meta: { has_more: false, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query), metric_labels: { percentage: "Percentage" } } }
        else
          events = Ahoy::Visit.scoped_events(range, filters)
          expr = "COALESCE(ahoy_events.properties->>'page', '(unknown)')"
          ev_rows = events.pluck(Arel.sql("visit_id, time, #{expr}"))
          last_page_by_visit = {}
          ev_rows.each do |vid, t, page_name|
            prev = last_page_by_visit[vid]
            t_val = t.respond_to?(:to_time) ? t.to_time : t
            prev_time = prev ? (prev.is_a?(Array) ? prev[0] : prev.first) : nil
            if prev.nil? || t_val > prev_time
              last_page_by_visit[vid] = [ t_val, page_name ]
            end
          end
          exit_groups = Hash.new { |h, k| h[k] = [] }
          last_page_by_visit.each { |vid, (_t, page_name)| exit_groups[page_name.to_s.presence || "(unknown)"] << vid }
          all_ids = exit_groups.values.flatten
          visitor_map = visits.where(id: all_ids).pluck(:id, :visitor_token).to_h
          unique_counts = exit_groups.transform_values { |ids| ids.filter_map { |vid| visitor_map[vid] }.uniq.size }
          total = Ahoy::Visit.percentage_total_visitors(visits)
          rows = unique_counts.sort_by { |_, v| -v }.map { |(name, v)| { name: name.to_s.presence || "(none)", visitors: v, percentage: (v.to_f / total).round(3) } }
          { results: rows, metrics: %i[visitors percentage], meta: { has_more: false, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query), metric_labels: { percentage: "Percentage" } } }
        end
      end
    end

    # Compute time_on_page and scroll_depth per page combining
    # legacy (page transitions) and new (engagement) approaches.
    def compute_time_on_page_and_scroll(range, filters, grouped_visit_ids)
      return {} if grouped_visit_ids.blank?

      names = grouped_visit_ids.keys
      all_visit_ids = grouped_visit_ids.values.flatten.uniq
      return {} if all_visit_ids.empty?

      events_scope = Ahoy::Visit.scoped_events(range, filters)
      ev_rows = events_scope.where(visit_id: all_visit_ids)
        .pluck(Arel.sql("visit_id, time, COALESCE(NULLIF(split_part(ahoy_events.properties->>'page', '?', 1), ''), '(unknown)')"))

      by_visit = Hash.new { |h, k| h[k] = [] }
      ev_rows.each { |vid, t, pg| by_visit[vid] << [ (t.respond_to?(:to_time) ? t.to_time : t), pg ] }
      by_visit.each_value { |arr| arr.sort_by!(&:first) }

      legacy_sum = Hash.new(0.0)
      legacy_cnt = Hash.new(0)
      eng_scope = Ahoy::Event
        .where(name: "engagement", time: range, visit_id: all_visit_ids)

      eng_rows = eng_scope
        .pluck(Arel.sql("visit_id, time, COALESCE(NULLIF(split_part(ahoy_events.properties->>'page', '?', 1), ''), '(unknown)'), (ahoy_events.properties->>'engaged_ms'), (ahoy_events.properties->>'scroll_depth')"))

      engaged_pages_by_visit = Hash.new { |h, k| h[k] = Set.new }
      eng_rows.each do |vid, _t, page, _engaged_ms, _scroll|
        engaged_pages_by_visit[vid] << (page.to_s.presence || "(unknown)")
      end

      by_visit.each do |vid, arr|
        next if arr.length <= 1
        (0...(arr.length - 1)).each do |i|
          t1, p1 = arr[i]
          t2, p2 = arr[i + 1]
          label = p1.to_s.presence || "(unknown)"
          next if p1 == p2
          next if engaged_pages_by_visit[vid].include?(label)
          delta = [ (t2 - t1).to_f, 0.0 ].max
          legacy_sum[label] += delta
          legacy_cnt[label] += 1
        end
      end

      new_sum = Hash.new(0.0)
      eng_seen_visit = Hash.new { |h, k| h[k] = Set.new }
      scroll_max_by_page_visit = Hash.new { |h, k| h[k] = {} }

      eng_rows.each do |vid, _t, page, engaged_ms, scroll|
        label = page.to_s.presence || "(unknown)"
        secs = begin
          v = engaged_ms.to_f
          (v > 0 ? v / 1000.0 : 0.0)
        rescue
          0.0
        end
        new_sum[label] += secs
        eng_seen_visit[label] << vid
        sd = begin
          s = scroll.to_f
          (s < 0 ? 0.0 : s)
        rescue
          0.0
        end
        prev = scroll_max_by_page_visit[label][vid]
        scroll_max_by_page_visit[label][vid] = sd if prev.nil? || sd > prev
      end

      names.each_with_object({}) do |name, result|
        total_time = legacy_sum[name].to_f + new_sum[name].to_f
        denom = legacy_cnt[name].to_i + eng_seen_visit[name]&.size.to_i
        top = denom > 0 ? (total_time / denom).round(1) : nil

        sd_map = scroll_max_by_page_visit[name] || {}
        scroll_depth = if sd_map.any?
          (sd_map.values.sum.to_f / sd_map.values.length.to_f).round
        else
          nil
        end

        result[name] = { time_on_page: top, scroll_depth: scroll_depth }
      end
    end

    def page_filter_metrics(range, filters, advanced_filters: [])
      visits = Ahoy::Visit.scoped_visits(range, filters, advanced_filters: advanced_filters)
      visit_ids = visits.pluck(:id)

      if visit_ids.empty?
        {
          visitors: 0,
          visits: 0,
          pageviews: 0,
          bounce_rate: 0.0,
          time_on_page: 0.0,
          scroll_depth: 0.0
        }
      else
        matcher = page_filter_matcher(filters, advanced_filters)
        rows = Ahoy::Event
          .where(name: "pageview", time: range, visit_id: visit_ids)
          .pluck(Arel.sql("visit_id, time, COALESCE(ahoy_events.properties->>'page', '')"))

        by_visit = Hash.new { |h, k| h[k] = [] }
        rows.each do |vid, time, page|
          by_visit[vid] << [ (time.respond_to?(:to_time) ? time.to_time : time), page.to_s ]
        end
        by_visit.each_value { |events| events.sort_by!(&:first) }

        matched_pageviews = 0
        legacy_sum = 0.0
        legacy_count = 0
        entry_visit_ids = []

        engagement_rows = Ahoy::Event
          .where(name: "engagement", time: range, visit_id: visit_ids)
          .pluck(Arel.sql("visit_id, time, COALESCE(ahoy_events.properties->>'page', ''), (ahoy_events.properties->>'engaged_ms'), (ahoy_events.properties->>'scroll_depth')"))

        engaged_pages_by_visit = Hash.new { |h, k| h[k] = Set.new }
        engagement_rows.each do |vid, _time, page, _engaged_ms, _scroll_depth|
          next unless matcher.call(page.to_s)

          engaged_pages_by_visit[vid] << (normalized_path_only(page).presence || page.to_s.presence || "(unknown)")
        end

        by_visit.each do |vid, events|
          next if events.empty?

          entry_visit_ids << vid if matcher.call(events.first.last)
          matched_pageviews += events.count { |_time, page| matcher.call(page) }

          next if events.length <= 1

          (0...(events.length - 1)).each do |index|
            time_a, page_a = events[index]
            time_b, page_b = events[index + 1]
            label = normalized_path_only(page_a).presence || page_a.to_s.presence || "(unknown)"
            next unless matcher.call(page_a)
            next if normalized_path_only(page_a) == normalized_path_only(page_b)
            next if engaged_pages_by_visit[vid].include?(label)

            legacy_sum += [ (time_b - time_a).to_f, 0.0 ].max
            legacy_count += 1
          end
        end

        engagement_sum = 0.0
        engagement_visits = Set.new
        max_scroll_by_visit = {}

        engagement_rows.each do |vid, _time, page, engaged_ms, scroll_depth|
          next unless matcher.call(page.to_s)

          engagement_sum += (engaged_ms.to_f.positive? ? engaged_ms.to_f / 1000.0 : 0.0)
          engagement_visits << vid

          scroll_value = [ scroll_depth.to_f, 0.0 ].max
          current_scroll = max_scroll_by_visit[vid]
          max_scroll_by_visit[vid] = scroll_value if current_scroll.nil? || scroll_value > current_scroll
        end

        entry_pageviews_by_visit = Ahoy::Event
          .where(name: "pageview", time: range, visit_id: entry_visit_ids)
          .group(:visit_id)
          .count
        non_pageview_visit_ids = Ahoy::Event
          .where(visit_id: entry_visit_ids)
          .where.not(name: "pageview")
          .distinct
          .pluck(:visit_id)
          .to_set

        bounces = entry_visit_ids.count do |visit_id|
          entry_pageviews_by_visit[visit_id].to_i == 1 && !non_pageview_visit_ids.include?(visit_id)
        end

        time_on_page_denominator = legacy_count + engagement_visits.size
        time_on_page =
          if time_on_page_denominator.positive?
            ((legacy_sum + engagement_sum) / time_on_page_denominator.to_f).round(1)
          else
            0.0
          end

        scroll_depth =
          if max_scroll_by_visit.any?
            (max_scroll_by_visit.values.sum.to_f / max_scroll_by_visit.size.to_f).round(2)
          else
            0.0
          end

        bounce_rate =
          if entry_visit_ids.any?
            ((bounces.to_f / entry_visit_ids.size.to_f) * 100.0).round(2)
          else
            0.0
          end

        {
          visitors: visits.distinct.count(:visitor_token),
          visits: visits.count,
          pageviews: matched_pageviews,
          bounce_rate: bounce_rate,
          time_on_page: time_on_page,
          scroll_depth: scroll_depth
        }
      end
    end

    def page_filter_matcher(filters, advanced_filters = [])
      basic_filters = filters.to_h
      advanced_page_filters = Array(advanced_filters).select { |_op, dim, _value| dim.to_s == "page" }

      lambda do |raw_page|
        page = raw_page.to_s
        normalized_page = normalized_path_only(page).to_s

        next false if basic_filters["page"].present? && page != basic_filters["page"].to_s
        next false if basic_filters["entry_page"].present? && normalized_page != basic_filters["entry_page"].to_s
        next false if basic_filters["exit_page"].present? && normalized_page != basic_filters["exit_page"].to_s

        advanced_page_filters.all? do |op, _dim, value|
          case op.to_s
          when "contains"
            page.downcase.include?(value.to_s.downcase)
          when "is_not"
            page != value.to_s
          else
            page == value.to_s
          end
        end
      end
    end

    def goal_denominator_counts_for_pages(query, mode:, search: nil)
      base_query = Ahoy::Visit.query_without_goal_and_props(query).merge(mode: mode)
      payload = pages_payload(base_query, search: search)
      payload.fetch(:results, []).each_with_object({}) do |row, counts|
        counts[row[:name].to_s] = row[:visitors].to_i
      end
    end

    def filter_page_groups!(grouped_visit_ids, counts, comparison_names, *extra_maps)
      return if comparison_names.empty?

      matcher = ->(name) { comparison_names.include?(formatted_page_name(name)) }
      grouped_visit_ids.select! { |name, _| matcher.call(name) }
      counts.select! { |name, _| matcher.call(name) }
      extra_maps.compact.each do |metrics_map|
        metrics_map.select! { |name, _| matcher.call(name) }
      end
    end

    def formatted_page_name(name)
      name.to_s.presence || "(none)"
    end

    # URL normalization helpers moved to Ahoy::Visit::UrlLabels

    def internal_entry_label?(label)
      path = label.to_s
      path.start_with?("/ahoy", "/cable", "/rails/", "/assets/", "/up", "/jobs", "/webhooks")
    end

    def entry_page_label_by_visit(visits_relation, subset_grouped)
      ids = subset_grouped.values.flatten.uniq
      return {} if ids.empty?
      visits_relation.where(id: ids).pluck(:id, :landing_page).each_with_object({}) do |(vid, lp), acc|
        acc[vid] = normalized_path_only(lp).presence || "(unknown)"
      end
    end

    def restrict_visits_to_entry_page(grouped_visit_ids, entry_label_by_visit)
      grouped_visit_ids.each_with_object({}) do |(name, ids), h|
        h[name] = ids.select { |vid| entry_label_by_visit[vid] == name }
      end
    end
  end
end
