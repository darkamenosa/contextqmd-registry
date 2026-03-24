require "zlib"

module Ahoy::Visit::Metrics
  extend ActiveSupport::Concern

  class_methods do
    def change_ratio(prev, curr)
      return nil if prev.nil?
      return 0 if prev.to_i <= 0
      ((curr.to_f - prev.to_f) / prev.to_f).round(4)
    end

    def visit_metrics(visits_scope, events_scope)
      total_visits = visits_scope.count

      live_visitors = Ahoy::Visit.live_visitors_count

      pageview_events_present = events_scope.exists?

      pageviews = 0
      views_per_visit = 0.0
      bounce_rate = 0.0
      average_duration = 0.0

      if pageview_events_present
        events_grouped = events_scope.group(:visit_id)
        pageviews_by_visit = events_grouped.count
        pageviews = pageviews_by_visit.values.sum

        visits_with_events = pageviews_by_visit.size
        unless visits_with_events.zero?
          views_per_visit = pageviews.to_f / visits_with_events

          durations_seconds = events_grouped.pluck(Arel.sql("GREATEST(EXTRACT(EPOCH FROM (MAX(time) - MIN(time))), 0)"))
          total_duration = durations_seconds.compact.sum
          average_duration = total_duration.to_f / visits_with_events
        end
      else
        pageviews = total_visits
        views_per_visit = total_visits.zero? ? 0.0 : (pageviews.to_f / total_visits)
      end

      if total_visits > 0
        pv_counts = pageview_events_present ? pageviews_by_visit : Hash.new(0)

        non_pv_ids = Ahoy::Event
          .where(visit_id: visits_scope.select(:id))
          .where.not(name: "pageview")
          .distinct
          .pluck(:visit_id)
          .to_set

        bounces = 0
        visits_scope.pluck(:id).each do |vid|
          pv = pv_counts[vid].to_i
          bounces += 1 if pv == 1 && !non_pv_ids.include?(vid)
        end
        bounce_rate = (bounces.to_f / total_visits.to_f * 100.0)
      end

      {
        total_visits: total_visits,
        live_visitors: live_visitors,
        pageviews: pageviews,
        pageviews_per_visit: views_per_visit,
        bounce_rate: bounce_rate,
        average_duration: average_duration
      }
    end

    def top_stats_payload(query)
      range, interval = Ahoy::Visit.range_and_interval_for(query[:period], query[:interval], query)
      filters = query[:filters] || {}
      adv = query[:advanced_filters] || []

      visits = Ahoy::Visit.scoped_visits(range, filters, advanced_filters: adv)
      events = Ahoy::Visit.scoped_events(range, filters, advanced_filters: adv)
      metrics = visit_metrics(visits, events)

      prev_range = case query[:comparison]
      when "year_over_year"
        r = Ahoy::Visit.year_over_year_range(range)
        r = Ahoy::Visit.align_comparison_weekday(r, range) if ActiveModel::Type::Boolean.new.cast(query[:match_day_of_week])
        r
      when "custom"
        Ahoy::Visit.custom_compare_range(query) || Ahoy::Visit.previous_range(range)
      when "previous_period"
        r = Ahoy::Visit.previous_range(range)
        r = Ahoy::Visit.align_comparison_weekday(r, range) if ActiveModel::Type::Boolean.new.cast(query[:match_day_of_week])
        r
      else
        Ahoy::Visit.previous_range(range)
      end

      prev_visits = Ahoy::Visit.scoped_visits(prev_range, filters, advanced_filters: adv)
      prev_events = Ahoy::Visit.scoped_events(prev_range, filters, advanced_filters: adv)
      prev_metrics = visit_metrics(prev_visits, prev_events)

      live_visitors = metrics[:live_visitors]
      uniques = visits.select(:visitor_token).distinct.count
      prev_uniques = prev_visits.select(:visitor_token).distinct.count

      total_visits = metrics[:total_visits]
      prev_total_visits = prev_metrics[:total_visits]

      pageviews = metrics[:pageviews]
      prev_pageviews = prev_metrics[:pageviews]

      stats = [
        { name: "Live visitors", value: live_visitors, graph_metric: :currentVisitors, change: nil, comparison_value: nil },
        { name: "Unique visitors", value: uniques, graph_metric: :visitors, change: change_ratio(prev_uniques, uniques), comparison_value: prev_uniques },
        { name: "Total visits", value: total_visits, graph_metric: :visits, change: change_ratio(prev_total_visits, total_visits), comparison_value: prev_total_visits },
        { name: "Total pageviews", value: pageviews, graph_metric: :pageviews, change: change_ratio(prev_pageviews, pageviews), comparison_value: prev_pageviews },
        {
          name: "Views per visit",
          value: metrics[:pageviews_per_visit].round(2),
          graph_metric: :views_per_visit,
          change: change_ratio(prev_metrics[:pageviews_per_visit], metrics[:pageviews_per_visit]),
          comparison_value: prev_metrics[:pageviews_per_visit]
        },
        {
          name: "Bounce rate",
          value: metrics[:bounce_rate].round(2),
          graph_metric: :bounce_rate,
          change: change_ratio(prev_metrics[:bounce_rate], metrics[:bounce_rate]),
          comparison_value: prev_metrics[:bounce_rate]
        },
        {
          name: "Visit duration",
          value: metrics[:average_duration].round(1),
          graph_metric: :visit_duration,
          change: change_ratio(prev_metrics[:average_duration], metrics[:average_duration]),
          comparison_value: prev_metrics[:average_duration]
        }
      ]

      {
        top_stats: stats,
        graphable_metrics: %w[visitors visits pageviews views_per_visit bounce_rate visit_duration],
        meta: { metric_warnings: {}, imports_included: false },
        interval: interval,
        includes_imported: false,
        with_imported_switch: { visible: false, togglable: false, tooltip_msg: nil },
        sample_percent: 100,
        from: range.begin.iso8601,
        to: range.end.iso8601,
        comparing_from: prev_range.begin.iso8601,
        comparing_to: prev_range.end.iso8601
      }
    end

    # Calculate bounce rate and visit duration for grouped visits
    # grouped_visit_ids: { label => [visit_id, ...] }
    def calculate_group_metrics(grouped_visit_ids, range, filters)
      return {} if grouped_visit_ids.empty?

      all_visit_ids = grouped_visit_ids.values.flatten
      return {} if all_visit_ids.empty?

      events_scope = Ahoy::Visit.scoped_events(range, filters)

      pageviews_by_visit = events_scope
        .where(visit_id: all_visit_ids)
        .group(:visit_id)
        .count

      non_pv_ids = Ahoy::Event
        .where(visit_id: all_visit_ids)
        .where.not(name: "pageview")
        .distinct
        .pluck(:visit_id)
        .to_set

      durations_by_visit = events_scope
        .where(visit_id: all_visit_ids)
        .group(:visit_id)
        .pluck(Arel.sql("visit_id, GREATEST(EXTRACT(EPOCH FROM (MAX(time) - MIN(time))), 0) as duration"))
        .to_h

      grouped_visit_ids.each_with_object({}) do |(name, visit_ids), result|
        denom = visit_ids.size
        if denom <= 0
          result[name] = { bounce_rate: nil, visit_duration: nil }
        else
          bounces = visit_ids.count { |vid| pageviews_by_visit[vid].to_i == 1 && !non_pv_ids.include?(vid) }
          bounce = (bounces.to_f / denom.to_f * 100.0).round(2)

          with_pv = visit_ids.select { |vid| durations_by_visit.key?(vid) }
          avg_duration = if with_pv.empty?
            0.0
          else
            with_pv.map { |vid| durations_by_visit[vid].to_f }.sum / with_pv.length
          end

          result[name] = { bounce_rate: bounce, visit_duration: avg_duration.round(1) }
        end
      end
    end

    # Unique visitor counts for grouped visit IDs using visitor_token
    def unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits_relation)
      return {} if grouped_visit_ids.empty?
      all_ids = grouped_visit_ids.values.flatten
      return {} if all_ids.empty?
      token_by_id = visits_relation.where(id: all_ids).pluck(:id, :visitor_token).to_h
      grouped_visit_ids.transform_values do |ids|
        ids.filter_map { |vid| token_by_id[vid] }.uniq.size
      end
    end

    # Compute conversions per group and conversion_rate
    def conversions_and_rates(grouped_visit_ids, visits_relation, range, filters, goal_name)
      return [ {}, {} ] if grouped_visit_ids.blank? || goal_name.blank?
      all_ids = grouped_visit_ids.values.flatten.uniq
      return [ {}, {} ] if all_ids.empty?

      token_by_id = visits_relation.where(id: all_ids).pluck(:id, :visitor_token).to_h

      goal_visit_ids = Ahoy::Event
        .joins(:visit)
        .merge(Ahoy::Visit.filtered_visits(filters))
        .where(name: goal_name, time: range, visit_id: all_ids)
        .distinct
        .pluck(:visit_id)
        .to_set

      uniques_by_group = unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits_relation)

      conversions = {}
      cr = {}
      grouped_visit_ids.each do |name, ids|
        tokens = ids.select { |vid| goal_visit_ids.include?(vid) }.filter_map { |vid| token_by_id[vid] }.uniq
        conversions[name] = tokens.size
        denom = uniques_by_group[name].to_i
        cr[name] = denom > 0 ? ((conversions[name].to_f / denom) * 100.0).round(2) : nil
      end

      [ conversions, cr ]
    end

    # Search Terms (demo via referrer parsing)
    def search_terms_payload(query, limit:, page:, search: nil, order_by: nil)
      range, = Ahoy::Visit.range_and_interval_for(query[:period], nil, query)
      filters = query[:filters] || {}

      visits = Ahoy::Visit.scoped_visits(range, filters)
        .where("referring_domain ~* ?", 'google\\.')
        .where.not(referrer: nil)

      rows = visits
        .pluck(:id, :referrer)
        .map do |id, ref|
          begin
            uri = URI.parse(ref)
            next nil unless uri.query
            q = CGI.parse(uri.query)["q"]&.first
            next nil if q.blank?
            [ q.downcase.strip, id ]
          rescue URI::InvalidURIError
            nil
          end
        end
        .compact

      grouped = Hash.new { |h, k| h[k] = [] }
      rows.each { |term, vid| grouped[term] << vid }

      if search.present?
        needle = search.downcase
        grouped.select! { |term, _| term.include?(needle) }
      end

      counts = grouped.transform_values(&:size)

      sorted_terms = if order_by
        metric, dir = order_by
        dir = (dir&.downcase == "asc") ? "asc" : "desc"
        case metric
        when "name"
          names = counts.keys.sort
          names.reverse! if dir == "desc"; names
        when "visitors", nil
          names = counts.sort_by { |k, v| [ v, k ] }.map(&:first)
          names.reverse! if dir == "desc"; names
        when "impressions", "ctr", "position"
          derived = counts.each_with_object({}) do |(k2, v2), h|
            h[k2.to_s] = fake_gsc_metrics_for(k: nil, term: k2, visitors: v2)
          end
          names = counts.keys.sort_by do |k|
            val = derived[k.to_s][metric.to_sym]
            [ val || -Float::INFINITY, k ]
          end
          names.reverse! if dir == "desc"; names
        when "bounce_rate", "visit_duration"
          metrics_all = calculate_group_metrics(grouped, range, filters)
          names = counts.keys.sort_by do |k|
            val = metrics_all.dig(k, metric.to_sym)
            [ val || -Float::INFINITY, k ]
          end
          names.reverse! if dir == "desc"; names
        else
          counts.sort_by { |k, v| [ v, k ] }.map(&:first).reverse
        end
      else
        counts.sort_by { |k, v| [ v, k ] }.map(&:first).reverse
      end

      paged_names, has_more = Ahoy::Visit.paginate_names(sorted_terms, limit: limit, page: page)

      page_visit_ids = grouped.slice(*paged_names)
      group_metrics = calculate_group_metrics(page_visit_ids, range, filters)

      results = paged_names.map do |term|
        visitors = counts[term]
        gsc = fake_gsc_metrics_for(k: nil, term: term, visitors: visitors)
        {
          name: term,
          visitors: visitors,
          impressions: gsc[:impressions],
          ctr: gsc[:ctr],
          position: gsc[:position]
        }
      end

      { results: results, metrics: %i[visitors impressions ctr position], meta: { has_more: has_more, skip_imported_reason: nil } }
    end

    def fake_gsc_metrics_for(k:, term:, visitors:)
      seed_str = (term || k || "").to_s
      crc = Zlib.crc32(seed_str)
      factor = 1.5 + (crc % 4850) / 100.0
      impressions = [ (visitors * factor).round, visitors ].max
      ctr = (visitors.to_f / impressions.to_f) * 100.0
      pos_int = (crc % 10) + 1
      pos_dec = ((crc / 10) % 10) / 10.0
      position = (pos_int + pos_dec).round(1)
      { impressions: impressions, ctr: ctr, position: position }
    end

    def behaviors_payload(query, limit: nil, page: nil, search: nil, order_by: nil)
      mode = (query[:mode] || "conversions").to_s
      range, = Ahoy::Visit.range_and_interval_for(query[:period], nil, query)
      filters = query[:filters] || {}
      visits = Ahoy::Visit.scoped_visits(range, filters)

      case mode
      when "props"
        props = {
          "utm_source" => visits.group(:utm_source).count,
          "utm_medium" => visits.group(:utm_medium).count,
          "utm_campaign" => visits.group(:utm_campaign).count
        }
        flat = props.flat_map do |k, counts|
          counts.map { |val, n| { name: k.humanize, value: val.to_s.presence || "(none)", visitors: n, percentage: 0.0 } }
        end
        { list: { results: flat, metrics: %i[visitors percentage], meta: { has_more: false, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query) } }, goal_highlighted: nil }
      when "funnels"
        names = Funnel.order(:name).pluck(:name)
        active_name = query[:funnel].presence || names.first
        return { funnels: names, active: { name: "", steps: [] } } if active_name.blank?

        funnel = Funnel.find_by(name: active_name)
        return { funnels: names, active: { name: "", steps: [] } } unless funnel

        ev_rows = Ahoy::Event
          .joins(:visit)
          .merge(Ahoy::Visit.filtered_visits(filters))
          .where(time: range)
          .pluck(Arel.sql("ahoy_events.visit_id, ahoy_events.time, ahoy_events.name, COALESCE(ahoy_events.properties->>'page', '')"))

        by_visit = Hash.new { |h, k| h[k] = [] }
        ev_rows.each { |vid, t, n, pg| by_visit[vid] << [ (t.respond_to?(:to_time) ? t.to_time : t), n.to_s, pg.to_s ] }
        by_visit.each_value { |arr| arr.sort_by!(&:first) }

        token_by_visit = visits.pluck(:id, :visitor_token).to_h

        sets = Array.new(funnel.steps.length) { Set.new }
        by_visit.each do |vid, arr|
          next if arr.empty?
          step_index = 0
          current_time = Time.at(0)
          while step_index < funnel.steps.length
            step = funnel.steps[step_index].to_h.with_indifferent_access
            typ = step[:type].to_s
            match = step[:match].to_s
            value = step[:value].to_s
            found = false
            arr.each do |t, name, page|
              next if t < current_time
              ok = case typ
              when "event"
                (match == "equals" ? (name == value) : name.include?(value))
              when "page"
                (match == "contains" ? page.include?(value) : page == value)
              else
                false
              end
              if ok
                current_time = t
                found = true
                break
              end
            end
            break unless found
            token = token_by_visit[vid]
            sets[step_index] << token if token.present?
            step_index += 1
          end
        end

        first_visitors = sets.first&.size.to_i
        steps = funnel.steps.each_with_index.map do |s, idx|
          s = s.with_indifferent_access
          v = sets[idx].size
          rate = first_visitors > 0 ? ((v.to_f / first_visitors.to_f) * 100.0) : 0.0
          label = s[:name] || s[:type].to_s.capitalize
          { name: label, visitors: v, conversion_rate: rate.round(2) }
        end

        { funnels: names, active: { name: funnel.name, steps: steps } }
      else
        events = Ahoy::Event
          .joins(:visit)
          .merge(Ahoy::Visit.filtered_visits(filters))
          .where(time: range)
          .where.not(name: [ "pageview", "engagement" ])

        grouped_visit_ids = events.group(:name).pluck(:name, Arel.sql("ARRAY_AGG(ahoy_events.visit_id)")).to_h
        uniques_by_group = unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits)

        total_uniques = visits.select(:visitor_token).distinct.count
        total_uniques = 1 if total_uniques <= 0

        conversions = {}
        rows = grouped_visit_ids.map do |goal_name, visit_ids|
          token_by_id = visits.where(id: visit_ids).pluck(:id, :visitor_token).to_h
          conv = visit_ids.filter_map { |vid| token_by_id[vid] }.uniq.size
          conversions[goal_name] = conv
          rate = (conv.to_f / total_uniques.to_f) * 100.0
          { name: goal_name.to_s, visitors: conv, conversion_rate: rate.round(2) }
        end

        if search.present?
          needle = search.downcase
          rows.select! { |r| r[:name].downcase.include?(needle) }
        end

        rows = if order_by
          metric, dir = order_by
          dir = (dir&.downcase == "asc") ? 1 : -1
          rows.sort_by do |r|
            key = case metric
            when "name" then r[:name].downcase
            when "conversion_rate" then r[:conversion_rate] || -Float::INFINITY
            else r[:visitors].to_i
            end
            key
          end
          dir == -1 ? rows.reverse : rows
        else
          rows.sort_by { |r| [ -r[:visitors].to_i, r[:name].downcase ] }
        end

        if limit && page
          window, has_more = Ahoy::Visit.paginate_names(rows, limit: limit, page: page)
          { results: window, metrics: %i[visitors conversion_rate], meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query) }, goal_highlighted: nil }
        else
          { results: rows, metrics: %i[visitors conversion_rate], meta: { has_more: false, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query) } }
        end
      end
    end
  end
end
