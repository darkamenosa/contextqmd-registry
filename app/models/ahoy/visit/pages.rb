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
      range, = Ahoy::Visit.range_and_interval_for(query[:period], nil, query)
      adv = query[:advanced_filters] || []
      visits = Ahoy::Visit.scoped_visits(range, filters, advanced_filters: adv)
      goal = filters["goal"].presence

      column = case mode
      when "entry" then :landing_page
      when "exit" then :landing_page
      else :landing_page
      end

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

          sorted_names = begin
            if order_by
              metric, _ = order_by
              case metric
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
            conversions, cr = Ahoy::Visit.conversions_and_rates(grouped_visit_ids, visits, range, filters, goal)
            sorted_names = Ahoy::Visit.order_names_with_conversions(conversions: conversions, cr: cr, order_by: order_by)

            paged_names, has_more = Ahoy::Visit.paginate_names(sorted_names, limit: limit, page: page)

            results = paged_names.map do |name|
              {
                name: name.to_s.presence || "(none)",
                visitors: conversions[name] || 0,
                conversion_rate: cr[name]
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

            { results: results, metrics: %i[visitors pageviews bounce_rate time_on_page scroll_depth], meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query) } }
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

          if goal.present?
            conversions, cr = Ahoy::Visit.conversions_and_rates(grouped_visit_ids, visits, range, filters, goal)
            sorted_names = Ahoy::Visit.order_names_with_conversions(conversions: conversions, cr: cr, order_by: order_by)

            paged_names, has_more = Ahoy::Visit.paginate_names(sorted_names, limit: limit, page: page)

            results = paged_names.map do |name|
              {
                name: name.to_s.presence || "(none)",
                visitors: conversions[name] || 0,
                conversion_rate: cr[name]
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
              metrics: %i[visitors visits bounce_rate visit_duration],
              meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query), metric_labels: { visits: "Total Entrances" } }
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

          pageviews_by_page = events.group(Arel.sql(expr)).count
          exit_rate_by_page = {}
          exits_by_page.each do |name, exits|
            pv = pageviews_by_page[name] || 0
            exit_rate_by_page[name] = pv > 0 ? (exits.to_f / pv.to_f * 100.0).round(2) : 0.0
          end

          if goal.present?
            grouped_visit_ids = exit_groups
            conversions, cr = Ahoy::Visit.conversions_and_rates(grouped_visit_ids, visits, range, filters, goal)
            sorted_names = Ahoy::Visit.order_names_with_conversions(conversions: conversions, cr: cr, order_by: order_by)

            paged_names, has_more = Ahoy::Visit.paginate_names(sorted_names, limit: limit, page: page)

            results = paged_names.map do |name|
              { name: name.to_s.presence || "(none)", visitors: conversions[name] || 0, conversion_rate: cr[name] }
            end

            { results: results, metrics: %i[visitors conversion_rate], meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query), metric_labels: { visitors: "Conversions", conversionRate: "Conversion Rate" } } }
          else
            sorted_names = begin
              if order_by
                metric, _ = order_by
                case metric
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

            { results: results, metrics: %i[visitors visits exit_rate], meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query), metric_labels: { visits: "Total Exits", exitRate: "Exit Rate" } } }
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
          rows = counts.sort_by { |_, v| -v }.map { |(name, v)| { name: name.to_s.presence || "(none)", visitors: v } }
          { results: rows, metrics: %i[visitors], meta: { has_more: false, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query) } }
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
          rows = counts.sort_by { |_, v| -v }.map { |(name, v)| { name: name.to_s.presence || "(none)", visitors: v } }
          { results: rows, metrics: %i[visitors], meta: { has_more: false, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query) } }
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
          rows = unique_counts.sort_by { |_, v| -v }.map { |(name, v)| { name: name.to_s.presence || "(none)", visitors: v } }
          { results: rows, metrics: %i[visitors], meta: { has_more: false, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query) } }
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

      cutoff = Ahoy::Event
        .joins(:visit)
        .merge(Ahoy::Visit.filtered_visits(filters))
        .where(name: "engagement", time: range)
        .minimum(:time)

      events_scope = Ahoy::Visit.scoped_events(range, filters)
      ev_rows = events_scope.where(visit_id: all_visit_ids)
        .pluck(Arel.sql("visit_id, time, COALESCE(NULLIF(split_part(ahoy_events.properties->>'page', '?', 1), ''), '(unknown)')"))

      by_visit = Hash.new { |h, k| h[k] = [] }
      ev_rows.each { |vid, t, pg| by_visit[vid] << [ (t.respond_to?(:to_time) ? t.to_time : t), pg ] }
      by_visit.each_value { |arr| arr.sort_by!(&:first) }

      legacy_sum = Hash.new(0.0)
      legacy_cnt = Hash.new(0)
      by_visit.each_value do |arr|
        next if arr.length <= 1
        (0...(arr.length - 1)).each do |i|
          t1, p1 = arr[i]
          t2, p2 = arr[i + 1]
          next if p1 == p2
          next if cutoff && t1 >= cutoff
          delta = [ (t2 - t1).to_f, 0.0 ].max
          legacy_sum[p1] += delta
          legacy_cnt[p1] += 1
        end
      end

      eng_scope = Ahoy::Event
        .joins(:visit)
        .merge(Ahoy::Visit.filtered_visits(filters))
        .where(name: "engagement", time: range, visit_id: all_visit_ids)

      eng_rows = eng_scope
        .pluck(Arel.sql("visit_id, time, COALESCE(NULLIF(split_part(ahoy_events.properties->>'page', '?', 1), ''), '(unknown)'), (ahoy_events.properties->>'engaged_ms'), (ahoy_events.properties->>'scroll_depth')"))

      new_sum = Hash.new(0.0)
      eng_seen_visit = Hash.new { |h, k| h[k] = Set.new }
      scroll_max_by_page_visit = Hash.new { |h, k| h[k] = {} }

      eng_rows.each do |vid, t, page, engaged_ms, scroll|
        t_val = (t.respond_to?(:to_time) ? t.to_time : t)
        next if cutoff && t_val < cutoff
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
