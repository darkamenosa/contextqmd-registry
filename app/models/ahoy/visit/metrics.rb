require "zlib"

module Ahoy::Visit::Metrics
  extend ActiveSupport::Concern

  class_methods do
    def top_stat_change(metric, prev, curr)
      return nil if prev.nil?

      case metric.to_s
      when "conversion_rate", "exit_rate"
        (curr.to_f - prev.to_f).round(1)
      when "bounce_rate"
        if prev.to_f.positive?
          (curr.to_f - prev.to_f).round(1)
        end
      else
        top_stat_percent_change(prev, curr)
      end
    end

    def top_stat_percent_change(prev, curr)
      if prev.nil? || curr.nil?
        nil
      elsif prev.to_f.zero? && curr.to_f.positive?
        100
      elsif prev.to_f.zero? && curr.to_f.zero?
        0
      else
        (((curr.to_f - prev.to_f) / prev.to_f) * 100).round
      end
    end

    def goal_filter_applied?(filters)
      filters.to_h["goal"].present?
    end

    def page_filter_applied?(filters, advanced_filters = [])
      base_filters = filters.to_h
      base_filters["page"].present? ||
        Array(advanced_filters).any? { |_op, dim, _value| dim.to_s == "page" }
    end

    def filters_without_goal_and_props(filters)
      filters.to_h.reject { |key, _value| key.to_s == "goal" || prop_filter_key?(key) }
    end

    def filters_without_goal(filters)
      filters.to_h.reject { |key, _value| key.to_s == "goal" }
    end

    def advanced_filters_without_goal_and_props(advanced_filters)
      Array(advanced_filters).reject do |_op, dim, _value|
        dim.to_s == "goal" || prop_filter_key?(dim)
      end
    end

    def advanced_filters_without_goal(advanced_filters)
      Array(advanced_filters).reject do |_op, dim, _value|
        dim.to_s == "goal"
      end
    end

    def percentage_total_visitors(visits_scope)
      visits_scope.distinct.count(:visitor_token).nonzero? || 1
    end

    def comparison_names_filter(query)
      Array(query[:comparison_names]).filter_map do |name|
        normalized = name.to_s.strip
        normalized.presence
      end
    end

    def comparison_codes_filter(query)
      Array(query[:comparison_codes]).filter_map do |code|
        normalized = code.to_s.strip.upcase
        normalized.presence
      end
    end

    def normalize_string_list(values)
      Array(values).filter_map do |value|
        normalized = value.to_s.strip
        normalized.presence
      end.uniq.sort
    end

    def managed_goal_definitions?
      Goal.exists? || AnalyticsSetting.get_bool("goals_managed", fallback: false)
    end

    def managed_property_keys?
      AnalyticsSetting.exists?(key: "allowed_event_props")
    end

    def configured_property_keys
      normalize_string_list(AnalyticsSetting.get_json("allowed_event_props", fallback: []))
    end

    def available_goal_names
      if managed_goal_definitions?
        Goal.order(:display_name).pluck(:display_name)
      else
        legacy = AnalyticsSetting.get_json("goals", fallback: :missing)
        if legacy == :missing
          Ahoy::Event.where.not(name: [ "pageview", "engagement" ]).distinct.order(:name).pluck(:name)
        else
          normalize_string_list(legacy)
        end
      end
    end

    def goals_available?
      if managed_goal_definitions?
        Goal.exists?
      else
        legacy = AnalyticsSetting.get_json("goals", fallback: :missing)
        if legacy == :missing
          Ahoy::Event.where.not(name: [ "pageview", "engagement" ]).limit(1).exists?
        else
          normalize_string_list(legacy).any?
        end
      end
    end

    def available_property_keys(events = nil)
      return configured_property_keys if managed_property_keys?

      scope = events || Ahoy::Event.where.not(properties: [ nil, {} ])
      behaviors_property_keys(scope)
    end

    def properties_available?
      if managed_property_keys?
        configured_property_keys.any?
      else
        Ahoy::Event.where.not(properties: [ nil, {} ]).limit(1).exists?
      end
    end

    def configured_goal(name)
      return unless managed_goal_definitions?

      Goal.find_by(display_name: name.to_s)
    end

    def goal_events_scope(range, filters, advanced_filters: [])
      goal_name = filters.to_h["goal"].presence
      return Ahoy::Event.none if goal_name.blank?

      base_filters = filters_without_goal(filters)
      base_advanced_filters = advanced_filters_without_goal(advanced_filters)
      visits = Ahoy::Visit.scoped_visits(range, base_filters, advanced_filters: base_advanced_filters)

      events = Ahoy::Event
        .joins(:visit)
        .merge(visits)
        .where(time: range)

      if (goal = configured_goal(goal_name))
        events = apply_configured_goal(events, goal)
      else
        events = events.where(name: goal_name)
      end

      events
    end

    def goal_metric_totals(range, filters, advanced_filters: [])
      goal_events = goal_events_scope(range, filters, advanced_filters: advanced_filters)
      conversion_visits = Ahoy::Visit.where(id: goal_events.select(:visit_id))
      unique_conversions = conversion_visits.distinct.count(:visitor_token)
      total_conversions = goal_events.count

      total_visits = Ahoy::Visit.scoped_visits(
        range,
        filters_without_goal_and_props(filters),
        advanced_filters: advanced_filters_without_goal_and_props(advanced_filters)
      )
      total_visitors = total_visits.distinct.count(:visitor_token)

      conversion_rate =
        if total_visitors.positive?
          ((unique_conversions.to_f / total_visitors.to_f) * 100.0).round(2)
        else
          0.0
        end

      {
        unique_conversions: unique_conversions,
        total_conversions: total_conversions,
        conversion_rate: conversion_rate
      }
    end

    def query_without_goal_and_props(query)
      query.to_h.deep_symbolize_keys.merge(
        filters: filters_without_goal_and_props(query[:filters] || {}),
        advanced_filters: advanced_filters_without_goal_and_props(query[:advanced_filters] || [])
      )
    end

    def apply_configured_goal(events, goal)
      page_match_expr = "COALESCE(NULLIF(split_part(ahoy_events.properties->>'page', CHR(63), 1), ''), '/')"

      case goal.type
      when :event
        events = events.where(name: goal.event_name)
      when :page
        events = events
          .where(name: "pageview")
        if goal.page_path.to_s.include?("*")
          events = events.where("#{page_match_expr} ~ ?", wildcard_goal_regex(goal.page_path))
        else
          events = events.where("#{page_match_expr} = ?", goal.page_path)
        end
      when :scroll
        events = events
          .where(name: "engagement")
          .where("COALESCE((ahoy_events.properties->>'scroll_depth')::float, 0) >= ?", goal.scroll_threshold.to_f)
        if goal.page_path.to_s.include?("*")
          events = events.where("#{page_match_expr} ~ ?", wildcard_goal_regex(goal.page_path))
        else
          events = events.where("#{page_match_expr} = ?", goal.page_path)
        end
      end

      apply_goal_custom_props(events, goal.custom_props)
    end

    def wildcard_goal_regex(page_path)
      if page_path.to_s.end_with?("*") && !page_path.to_s.end_with?("**") && page_path.to_s.count("*") == 1
        base = Regexp.escape(page_path.to_s.delete_suffix("*"))
        return "^#{base}(?:$|/.*)$"
      end

      escaped =
        page_path.to_s
          .yield_self { |value| Regexp.escape(value) }
          .gsub("\\*\\*", "__DOUBLE_WILDCARD__")
          .gsub("\\*", "[^/]*")
          .gsub("__DOUBLE_WILDCARD__", ".*")

      "^#{escaped}$"
    end

    def apply_goal_custom_props(events, custom_props)
      Array(custom_props&.to_h).reduce(events) do |scope, (key, value)|
        prop_name = key.to_s.strip
        prop_value = value.to_s.strip
        next scope if prop_name.blank? || prop_value.blank?

        scope
          .where(behaviors_property_exists_expr(prop_name))
          .where(behaviors_property_value_expr(prop_name).eq(prop_value))
      end
    end

    def goal_conversion_rate(conversions, denominator)
      denom = denominator.to_i
      return 0.0 if denom <= 0

      ((conversions.to_f / denom.to_f) * 100.0).round(2)
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
          views_per_visit = total_visits.zero? ? 0.0 : (pageviews.to_f / total_visits.to_f)

          durations_seconds = events_grouped.pluck(Arel.sql("GREATEST(EXTRACT(EPOCH FROM (MAX(time) - MIN(time))), 0)"))
          total_duration = durations_seconds.compact.sum
          average_duration = total_visits.zero? ? 0.0 : (total_duration.to_f / total_visits.to_f)
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
      raw_range, interval = Ahoy::Visit.range_and_interval_for(query[:period], query[:interval], query)
      range = Ahoy::Visit.trim_range_to_now_if_applicable(raw_range, query[:period])
      filters = query[:filters] || {}
      adv = query[:advanced_filters] || []

      prev_range =
        Ahoy::Visit.comparison_range_for(query, raw_range, effective_source_range: range) ||
        Ahoy::Visit.previous_range(range)

      live_visitors = Ahoy::Visit.live_visitors_count
      stats = [ { name: "Live visitors", value: live_visitors, graph_metric: :currentVisitors, change: nil, comparison_value: nil } ]
      graphable_metrics =
        if goal_filter_applied?(filters)
          metrics = goal_metric_totals(range, filters, advanced_filters: adv)
          prev_metrics = goal_metric_totals(prev_range, filters, advanced_filters: adv)

          stats.concat([
            {
              name: "Unique conversions",
              value: metrics[:unique_conversions],
              graph_metric: :visitors,
              change: top_stat_change(:visitors, prev_metrics[:unique_conversions], metrics[:unique_conversions]),
              comparison_value: prev_metrics[:unique_conversions]
            },
            {
              name: "Total conversions",
              value: metrics[:total_conversions],
              graph_metric: :events,
              change: top_stat_change(:events, prev_metrics[:total_conversions], metrics[:total_conversions]),
              comparison_value: prev_metrics[:total_conversions]
            },
            {
              name: "Conversion rate",
              value: metrics[:conversion_rate],
              graph_metric: :conversion_rate,
              change: top_stat_change(:conversion_rate, prev_metrics[:conversion_rate], metrics[:conversion_rate]),
              comparison_value: prev_metrics[:conversion_rate]
            }
          ])
          %w[visitors events conversion_rate]
        else
          visits = Ahoy::Visit.scoped_visits(range, filters, advanced_filters: adv)
          events = Ahoy::Visit.scoped_events(range, filters, advanced_filters: adv)
          metrics = visit_metrics(visits, events)
          prev_visits = Ahoy::Visit.scoped_visits(prev_range, filters, advanced_filters: adv)
          prev_events = Ahoy::Visit.scoped_events(prev_range, filters, advanced_filters: adv)
          prev_metrics = visit_metrics(prev_visits, prev_events)
          uniques = visits.select(:visitor_token).distinct.count
          prev_uniques = prev_visits.select(:visitor_token).distinct.count

          if page_filter_applied?(filters, adv)
            page_metrics = Ahoy::Visit.page_filter_metrics(range, filters, advanced_filters: adv)
            prev_page_metrics = Ahoy::Visit.page_filter_metrics(prev_range, filters, advanced_filters: adv)

            stats.concat([
              { name: "Unique visitors", value: uniques, graph_metric: :visitors, change: top_stat_change(:visitors, prev_uniques, uniques), comparison_value: prev_uniques },
              { name: "Total visits", value: metrics[:total_visits], graph_metric: :visits, change: top_stat_change(:visits, prev_metrics[:total_visits], metrics[:total_visits]), comparison_value: prev_metrics[:total_visits] },
              { name: "Total pageviews", value: metrics[:pageviews], graph_metric: :pageviews, change: top_stat_change(:pageviews, prev_metrics[:pageviews], metrics[:pageviews]), comparison_value: prev_metrics[:pageviews] },
              {
                name: "Bounce rate",
                value: page_metrics[:bounce_rate],
                graph_metric: :bounce_rate,
                change: top_stat_change(:bounce_rate, prev_page_metrics[:bounce_rate], page_metrics[:bounce_rate]),
                comparison_value: prev_page_metrics[:bounce_rate]
              },
              {
                name: "Scroll depth",
                value: page_metrics[:scroll_depth],
                graph_metric: :scroll_depth,
                change: top_stat_change(:scroll_depth, prev_page_metrics[:scroll_depth], page_metrics[:scroll_depth]),
                comparison_value: prev_page_metrics[:scroll_depth]
              },
              {
                name: "Time on page",
                value: page_metrics[:time_on_page],
                graph_metric: :time_on_page,
                change: top_stat_change(:time_on_page, prev_page_metrics[:time_on_page], page_metrics[:time_on_page]),
                comparison_value: prev_page_metrics[:time_on_page]
              }
            ])
            %w[visitors visits pageviews bounce_rate scroll_depth time_on_page]
          else
            stats.concat([
              { name: "Unique visitors", value: uniques, graph_metric: :visitors, change: top_stat_change(:visitors, prev_uniques, uniques), comparison_value: prev_uniques },
              { name: "Total visits", value: metrics[:total_visits], graph_metric: :visits, change: top_stat_change(:visits, prev_metrics[:total_visits], metrics[:total_visits]), comparison_value: prev_metrics[:total_visits] },
              { name: "Total pageviews", value: metrics[:pageviews], graph_metric: :pageviews, change: top_stat_change(:pageviews, prev_metrics[:pageviews], metrics[:pageviews]), comparison_value: prev_metrics[:pageviews] },
              {
                name: "Views per visit",
                value: metrics[:pageviews_per_visit].round(2),
                graph_metric: :views_per_visit,
                change: top_stat_change(:views_per_visit, prev_metrics[:pageviews_per_visit], metrics[:pageviews_per_visit]),
                comparison_value: prev_metrics[:pageviews_per_visit]
              },
              {
                name: "Bounce rate",
                value: metrics[:bounce_rate].round(2),
                graph_metric: :bounce_rate,
                change: top_stat_change(:bounce_rate, prev_metrics[:bounce_rate], metrics[:bounce_rate]),
                comparison_value: prev_metrics[:bounce_rate]
              },
              {
                name: "Visit duration",
                value: metrics[:average_duration].round(1),
                graph_metric: :visit_duration,
                change: top_stat_change(:visit_duration, prev_metrics[:average_duration], metrics[:average_duration]),
                comparison_value: prev_metrics[:average_duration]
              }
            ])
            %w[visitors visits pageviews views_per_visit bounce_rate visit_duration]
          end
        end

      {
        top_stats: stats,
        graphable_metrics: graphable_metrics,
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

          avg_duration = if denom <= 0
            0.0
          else
            visit_ids.sum { |vid| durations_by_visit[vid].to_f } / denom.to_f
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
    def conversions_and_rates(grouped_visit_ids, visits_relation, range, filters, goal_name, advanced_filters: [], denominator_counts: nil)
      return [ {}, {} ] if grouped_visit_ids.blank? || goal_name.blank?
      all_ids = grouped_visit_ids.values.flatten.uniq
      return [ {}, {} ] if all_ids.empty?

      token_by_id = visits_relation.where(id: all_ids).pluck(:id, :visitor_token).to_h

      goal_visit_ids = goal_events_scope(range, filters, advanced_filters: advanced_filters)
        .where(visit_id: all_ids)
        .distinct
        .pluck(:visit_id)
        .to_set

      uniques_by_group = denominator_counts || unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits_relation)

      conversions = {}
      cr = {}
      grouped_visit_ids.each do |name, ids|
        tokens = ids.select { |vid| goal_visit_ids.include?(vid) }.filter_map { |vid| token_by_id[vid] }.uniq
        conversions[name] = tokens.size
        denom = uniques_by_group[name].to_i
        cr[name] = denom > 0 ? goal_conversion_rate(conversions[name], denom) : nil
      end

      [ conversions, cr ]
    end

    # Search Terms (demo via referrer parsing)
    def search_terms_payload(query, limit:, page:, search: nil, order_by: nil)
      range, = Ahoy::Visit.range_and_interval_for(query[:period], nil, query)
      filters = query[:filters] || {}
      comparison_names = comparison_names_filter(query)

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
      if comparison_names.any?
        grouped.select! { |term, _| comparison_names.include?(term.to_s) }
      end

      counts = unique_counts_from_grouped_visit_ids(grouped, visits)

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
      advanced_filters = query[:advanced_filters] || []
      comparison_names = comparison_names_filter(query)

      case mode
      when "props"
        visit_filters =
          if filters["goal"].present?
            filters_without_goal(filters)
          else
            filters_without_goal_and_props(filters)
          end
        visit_advanced_filters =
          if filters["goal"].present?
            advanced_filters_without_goal(advanced_filters)
          else
            advanced_filters_without_goal_and_props(advanced_filters)
          end
        visits = Ahoy::Visit.scoped_visits(
          range,
          visit_filters,
          advanced_filters: visit_advanced_filters
        )
        events = behaviors_props_scope(range, filters, visits)
        property_keys = available_property_keys(events)
        active_property = query[:property].presence
        active_property = property_keys.first unless property_keys.include?(active_property)

        if active_property.blank?
          return {
            list: {
              results: [],
              metrics: filters["goal"].present? ? %i[visitors events conversion_rate] : %i[visitors events percentage],
              meta: {
                has_more: false,
                skip_imported_reason: Ahoy::Visit.skip_imported_reason(query),
                metric_labels: { events: "Events" }
              }
            },
            property_keys: [],
            active_property: nil,
            goal_highlighted: nil
          }
        end

        value_expr = behaviors_property_value_expr(active_property)
        property_events = events.where(behaviors_property_exists_expr(active_property))
        unless filters["goal"].present?
          property_events = apply_property_filters_to_events(property_events, filters)
          property_events = apply_property_filters_to_events(property_events, advanced_filters)
        end
        if search.present?
          property_events = property_events.where(
            behaviors_property_value_lower_expr(active_property).matches(like_contains(search))
          )
        end

        visitor_counts = property_events.group(value_expr).count("DISTINCT ahoy_visits.visitor_token")
        total_counts = property_events.group(value_expr).count
        if comparison_names.any?
          visitor_counts.select! { |name, _| comparison_names.include?(name.to_s) }
          total_counts.select! { |name, _| comparison_names.include?(name.to_s) }
        end

        if filters["goal"].present?
          total_uniques = Ahoy::Visit.scoped_visits(
            range,
            filters_without_goal_and_props(filters),
            advanced_filters: advanced_filters_without_goal_and_props(advanced_filters)
          ).select(:visitor_token).distinct.count
          total_uniques = 1 if total_uniques <= 0
          metrics_map = visitor_counts.keys.index_with do |name|
            {
              events: total_counts[name].to_i,
              conversion_rate: ((visitor_counts[name].to_f / total_uniques.to_f) * 100.0).round(2)
            }
          end
        else
          total_visitors = property_events.distinct.count("ahoy_visits.visitor_token")
          total_visitors = 1 if total_visitors <= 0
          metrics_map = visitor_counts.keys.index_with do |name|
            {
              events: total_counts[name].to_i,
              percentage: (visitor_counts[name].to_f / total_visitors).round(3)
            }
          end
        end

        sorted_names = Ahoy::Visit.order_names(counts: visitor_counts, metrics_map: metrics_map, order_by: order_by)

        if limit && page
          paged_names, has_more = Ahoy::Visit.paginate_names(sorted_names, limit: limit, page: page)
          rows = paged_names.map do |name|
            visitors = visitor_counts[name].to_i
            row = { name: name.to_s, visitors: visitors, events: total_counts[name].to_i }
            if filters["goal"].present?
              row[:conversion_rate] = metrics_map.dig(name, :conversion_rate)
            else
              row[:percentage] = metrics_map.dig(name, :percentage)
            end
            row
          end
          {
            list: {
              results: rows,
              metrics: filters["goal"].present? ? %i[visitors events conversion_rate] : %i[visitors events percentage],
              meta: {
                has_more: has_more,
                skip_imported_reason: Ahoy::Visit.skip_imported_reason(query),
                metric_labels: { events: "Events" }
              }
            },
            property_keys: property_keys,
            active_property: active_property,
            goal_highlighted: nil
          }
        else
          rows = sorted_names.map do |name|
            visitors = visitor_counts[name].to_i
            row = { name: name.to_s, visitors: visitors, events: total_counts[name].to_i }
            if filters["goal"].present?
              row[:conversion_rate] = metrics_map.dig(name, :conversion_rate)
            else
              row[:percentage] = metrics_map.dig(name, :percentage)
            end
            row
          end
          {
            list: {
              results: rows,
              metrics: filters["goal"].present? ? %i[visitors events conversion_rate] : %i[visitors events percentage],
              meta: {
                has_more: false,
                skip_imported_reason: Ahoy::Visit.skip_imported_reason(query),
                metric_labels: { events: "Events" }
              }
            },
            property_keys: property_keys,
            active_property: active_property,
            goal_highlighted: nil
          }
        end
      when "funnels"
        visits = Ahoy::Visit.scoped_visits(range, filters, advanced_filters: advanced_filters)
        names = Funnel.order(:name).pluck(:name)
        active_name = query[:funnel].presence || names.first
        return { funnels: names, active: { name: "", steps: [] } } if active_name.blank?

        funnel = Funnel.find_by(name: active_name)
        return { funnels: names, active: { name: "", steps: [] } } unless funnel

        ev_rows = Ahoy::Event
          .joins(:visit)
          .merge(visits)
          .where(time: range)
          .pluck(Arel.sql("ahoy_events.visit_id, ahoy_events.time, ahoy_events.name, COALESCE(ahoy_events.properties->>'page', '')"))

        by_visit = Hash.new { |h, k| h[k] = [] }
        ev_rows.each { |vid, t, n, pg| by_visit[vid] << [ (t.respond_to?(:to_time) ? t.to_time : t), n.to_s, pg.to_s ] }
        by_visit.each_value { |arr| arr.sort_by!(&:first) }

        token_by_visit = visits.pluck(:id, :visitor_token).to_h
        total_visitors = visits.distinct.count(:visitor_token)

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

        entering_visitors = sets.first&.size.to_i
        never_entering_visitors = [ total_visitors - entering_visitors, 0 ].max
        entering_visitors_percentage =
          if total_visitors.positive?
            ((entering_visitors.to_f / total_visitors.to_f) * 100.0).round(2)
          else
            0.0
          end
        never_entering_visitors_percentage =
          if total_visitors.positive?
            ((never_entering_visitors.to_f / total_visitors.to_f) * 100.0).round(2)
          else
            0.0
          end

        steps = funnel.steps.each_with_index.map do |s, idx|
          s = s.with_indifferent_access
          v = sets[idx].size
          previous_visitors = idx.zero? ? entering_visitors : sets[idx - 1].size
          dropoff =
            if idx.zero?
              never_entering_visitors
            else
              [ previous_visitors - v, 0 ].max
            end
          conversion_rate =
            if entering_visitors.positive?
              ((v.to_f / entering_visitors.to_f) * 100.0).round(2)
            else
              0.0
            end
          conversion_rate_step =
            if idx.zero?
              entering_visitors_percentage
            elsif previous_visitors.positive?
              ((v.to_f / previous_visitors.to_f) * 100.0).round(2)
            else
              0.0
            end
          dropoff_percentage =
            if idx.zero?
              never_entering_visitors_percentage
            elsif previous_visitors.positive?
              ((dropoff.to_f / previous_visitors.to_f) * 100.0).round(2)
            else
              0.0
            end
          label = s[:name] || s[:type].to_s.capitalize
          {
            name: label,
            visitors: v,
            conversion_rate: conversion_rate,
            conversion_rate_step: conversion_rate_step,
            dropoff: dropoff,
            dropoff_percentage: dropoff_percentage
          }
        end

        overall_conversion_rate = steps.last&.dig(:conversion_rate).to_f.round(2)

        {
          funnels: names,
          active: {
            name: funnel.name,
            conversion_rate: overall_conversion_rate,
            entering_visitors: entering_visitors,
            entering_visitors_percentage: entering_visitors_percentage,
            never_entering_visitors: never_entering_visitors,
            never_entering_visitors_percentage: never_entering_visitors_percentage,
            steps: steps
          }
        }
      else
        goal_names = available_goal_names
        names = goal_names
        names = names.select { |name| comparison_names.include?(name.to_s) } if comparison_names.any?

        rows = names.map do |goal_name|
          totals = goal_metric_totals(
            range,
            filters.to_h.merge("goal" => goal_name.to_s),
            advanced_filters: advanced_filters
          )

          {
            name: goal_name.to_s,
            uniques: totals[:unique_conversions],
            total: totals[:total_conversions],
            conversion_rate: totals[:conversion_rate]
          }
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
            when "total" then r[:total].to_i
            when "conversion_rate" then r[:conversion_rate] || -Float::INFINITY
            else r[:uniques].to_i
            end
            key
          end
          dir == -1 ? rows.reverse : rows
        else
          rows.sort_by { |r| [ -r[:uniques].to_i, r[:name].downcase ] }
        end

        if limit && page
          window, has_more = Ahoy::Visit.paginate_names(rows, limit: limit, page: page)
          { results: window, metrics: %i[uniques total conversion_rate], meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query) }, goal_highlighted: nil }
        else
          { results: rows, metrics: %i[uniques total conversion_rate], meta: { has_more: false, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query) } }
        end
      end
    end

    def behaviors_props_scope(range, filters, visits)
      events = Ahoy::Event
        .joins(:visit)
        .merge(visits)
        .where(time: range)
        .where.not(properties: [ nil, {} ])

      if filters["goal"].present?
        if (goal = configured_goal(filters["goal"]))
          apply_configured_goal(events, goal)
        else
          events.where(name: filters["goal"])
        end
      else
        events.where.not(name: [ "pageview", "engagement" ])
      end
    end

    def behaviors_property_keys(events)
      rows = connection.select_values(<<~SQL.squish)
        SELECT DISTINCT key
        FROM (#{events.select("jsonb_object_keys(ahoy_events.properties) AS key").to_sql}) property_keys
      SQL

      rows
        .map(&:to_s)
        .reject(&:blank?)
        .reject { |key| %w[page url title referrer screen_size engaged_ms scroll_depth].include?(key) }
        .sort
    end

    def behaviors_property_exists_expr(property_name)
      Arel::Nodes::InfixOperation.new("?", behaviors_properties_column, Arel::Nodes.build_quoted(property_name.to_s))
    end

    def behaviors_property_value_expr(property_name)
      value = Arel::Nodes::InfixOperation.new(
        "->>",
        behaviors_properties_column,
        Arel::Nodes.build_quoted(property_name.to_s)
      )
      blank_to_null = Arel::Nodes::NamedFunction.new("NULLIF", [ value, Arel::Nodes.build_quoted("") ])
      Arel::Nodes::NamedFunction.new("COALESCE", [ blank_to_null, Arel::Nodes.build_quoted("(none)") ])
    end

    def behaviors_property_value_lower_expr(property_name)
      Arel::Nodes::NamedFunction.new("LOWER", [ behaviors_property_value_expr(property_name) ])
    end

    def behaviors_properties_column
      Ahoy::Event.arel_table[:properties]
    end

    def apply_property_filters_to_events(events, filters)
      Array(filters).each do |entry|
        if entry.is_a?(Array) && entry.length == 3
          op, key, value = entry
        else
          key, value = entry
          op = "is"
        end
        next unless prop_filter_key?(key)
        property_name = prop_filter_name(key)
        next if property_name.blank? || value.to_s.strip.empty?

        value_expr = behaviors_property_value_expr(property_name)
        events = events.where(behaviors_property_exists_expr(property_name))
        case op.to_s
        when "contains"
          events = events.where(behaviors_property_value_lower_expr(property_name).matches(like_contains(value)))
        when "is_not"
          events = events.where(value_expr.not_eq(value.to_s))
        else
          events = events.where(value_expr.eq(value.to_s))
        end
      end
      events
    end
  end
end
