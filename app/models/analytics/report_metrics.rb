# frozen_string_literal: true

class Analytics::ReportMetrics
  class << self
    def percentage_total_visitors(visits_scope)
      visits_scope.distinct.count(:visitor_token).nonzero? || 1
    end

    def top_stat_change(metric, previous_value, current_value)
      return nil if previous_value.nil?

      case metric.to_s
      when "conversion_rate", "exit_rate"
        (current_value.to_f - previous_value.to_f).round(1)
      when "bounce_rate"
        if previous_value.to_f.positive?
          (current_value.to_f - previous_value.to_f).round(1)
        end
      else
        top_stat_percent_change(previous_value, current_value)
      end
    end

    def top_stat_percent_change(previous_value, current_value)
      if previous_value.nil? || current_value.nil?
        nil
      elsif previous_value.to_f.zero? && current_value.to_f.positive?
        100
      elsif previous_value.to_f.zero? && current_value.to_f.zero?
        0
      else
        (((current_value.to_f - previous_value.to_f) / previous_value.to_f) * 100).round
      end
    end

    def goal_conversion_rate(conversions, denominator)
      denom = denominator.to_i
      return 0.0 if denom <= 0

      ((conversions.to_f / denom.to_f) * 100.0).round(2)
    end

    def goal_events_scope(range, query_or_filters, advanced_filters: [])
      query = normalize_query(query_or_filters, advanced_filters:)
      goal_name = query.filter_value(:goal).presence
      return Ahoy::Event.none if goal_name.blank?

      base_query = query.without_goal
      visits = Analytics::VisitScope.visits(range, base_query)

      events = Ahoy::Event
        .joins(:visit)
        .merge(visits)
        .where(time: range)

      if (goal = Analytics::Goals.configured(goal_name))
        Analytics::Goals.apply(events, goal)
      else
        events.where(name: goal_name)
      end
    end

    def goal_metric_totals(range, query_or_filters, advanced_filters: [])
      query = normalize_query(query_or_filters, advanced_filters:)
      goal_events = goal_events_scope(range, query)
      conversion_visits = Ahoy::Visit.where(id: goal_events.select(:visit_id))
      unique_conversions = conversion_visits.distinct.count(:visitor_token)
      total_conversions = goal_events.count

      base_query = query.without_goal_or_properties(property_filter: ->(key) { Analytics::Properties.filter_key?(key) })
      total_visits = Analytics::VisitScope.visits(range, base_query)
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

    def visit_metrics(visits_scope, events_scope)
      total_visits = visits_scope.count
      live_visitors = Analytics::LiveState.current_visitors
      pageview_events_present = events_scope.exists?

      pageviews = 0
      views_per_visit = 0.0
      bounce_rate = 0.0
      average_duration = 0.0

      if pageview_events_present
        events_grouped = events_scope.group(:visit_id)
        pageviews_by_visit = events_grouped.count
        pageviews = pageviews_by_visit.values.sum

        unless pageviews_by_visit.empty?
          views_per_visit = total_visits.zero? ? 0.0 : (pageviews.to_f / total_visits.to_f)

          durations_seconds = events_grouped.pluck(Arel.sql("GREATEST(EXTRACT(EPOCH FROM (MAX(time) - MIN(time))), 0)"))
          total_duration = durations_seconds.compact.sum
          average_duration = total_visits.zero? ? 0.0 : (total_duration.to_f / total_visits.to_f)
        end
      else
        pageviews = total_visits
        views_per_visit = total_visits.zero? ? 0.0 : (pageviews.to_f / total_visits)
        pageviews_by_visit = Hash.new(0)
      end

      if total_visits.positive?
        non_pageview_ids = Ahoy::Event
          .where(visit_id: visits_scope.select(:id))
          .where.not(name: "pageview")
          .distinct
          .pluck(:visit_id)
          .to_set

        bounces = 0
        visits_scope.pluck(:id).each do |visit_id|
          pageviews_for_visit = pageviews_by_visit[visit_id].to_i
          bounces += 1 if pageviews_for_visit == 1 && !non_pageview_ids.include?(visit_id)
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

    def calculate_group_metrics(grouped_visit_ids, range, query_or_filters, advanced_filters: [])
      return {} if grouped_visit_ids.empty?

      all_visit_ids = grouped_visit_ids.values.flatten
      return {} if all_visit_ids.empty?

      query = normalize_query(query_or_filters, advanced_filters:)
      events_scope = Analytics::VisitScope.pageviews(range, query)

      pageviews_by_visit = events_scope
        .where(visit_id: all_visit_ids)
        .group(:visit_id)
        .count

      non_pageview_ids = Ahoy::Event
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
        denominator = visit_ids.size
        if denominator <= 0
          result[name] = { bounce_rate: nil, visit_duration: nil }
        else
          bounces = visit_ids.count { |visit_id| pageviews_by_visit[visit_id].to_i == 1 && !non_pageview_ids.include?(visit_id) }
          bounce_rate = (bounces.to_f / denominator.to_f * 100.0).round(2)
          average_duration = visit_ids.sum { |visit_id| durations_by_visit[visit_id].to_f } / denominator.to_f

          result[name] = {
            bounce_rate: bounce_rate,
            visit_duration: average_duration.round(1)
          }
        end
      end
    end

    def unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits_relation)
      return {} if grouped_visit_ids.empty?

      all_visit_ids = grouped_visit_ids.values.flatten
      return {} if all_visit_ids.empty?

      token_by_id = visits_relation.where(id: all_visit_ids).pluck(:id, :visitor_token).to_h
      grouped_visit_ids.transform_values do |visit_ids|
        visit_ids.filter_map { |visit_id| token_by_id[visit_id] }.uniq.size
      end
    end

    def conversions_and_rates(grouped_visit_ids, visits_relation, range, query_or_filters, goal_name = nil, advanced_filters: [], denominator_counts: nil)
      return [ {}, {} ] if grouped_visit_ids.blank?

      all_visit_ids = grouped_visit_ids.values.flatten.uniq
      return [ {}, {} ] if all_visit_ids.empty?

      query = normalize_query(query_or_filters, advanced_filters:)
      goal_name ||= query.filter_value(:goal).presence
      return [ {}, {} ] if goal_name.blank?

      token_by_id = visits_relation.where(id: all_visit_ids).pluck(:id, :visitor_token).to_h
      goal_visit_ids = goal_events_scope(range, query)
        .where(visit_id: all_visit_ids)
        .distinct
        .pluck(:visit_id)
        .to_set

      uniques_by_group = denominator_counts || unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits_relation)

      conversions = {}
      conversion_rates = {}
      grouped_visit_ids.each do |name, visit_ids|
        tokens = visit_ids.select { |visit_id| goal_visit_ids.include?(visit_id) }.filter_map { |visit_id| token_by_id[visit_id] }.uniq
        conversions[name] = tokens.size
        denominator = uniques_by_group[name].to_i
        conversion_rates[name] = denominator > 0 ? goal_conversion_rate(conversions[name], denominator) : nil
      end

      [ conversions, conversion_rates ]
    end

    def page_filter_metrics(range, query_or_filters, advanced_filters: [])
      query = normalize_query(query_or_filters, advanced_filters:)
      visits = Analytics::VisitScope.visits(range, query)
      visit_ids = visits.pluck(:id)

      return empty_page_filter_metrics if visit_ids.empty?

      matcher = page_filter_matcher(query)
      pageview_rows = Ahoy::Event
        .where(name: "pageview", time: range, visit_id: visit_ids)
        .pluck(Arel.sql("visit_id, time, COALESCE(ahoy_events.properties->>'page', '')"))

      visits_by_pageview = Hash.new { |hash, key| hash[key] = [] }
      pageview_rows.each do |visit_id, time, page|
        visits_by_pageview[visit_id] << [ (time.respond_to?(:to_time) ? time.to_time : time), page.to_s ]
      end
      visits_by_pageview.each_value { |events| events.sort_by!(&:first) }

      matched_pageviews = 0
      legacy_sum = 0.0
      legacy_count = 0
      entry_visit_ids = []

      engagement_rows = Ahoy::Event
        .where(name: "engagement", time: range, visit_id: visit_ids)
        .pluck(Arel.sql("visit_id, time, COALESCE(ahoy_events.properties->>'page', ''), (ahoy_events.properties->>'engaged_ms'), (ahoy_events.properties->>'scroll_depth')"))

      engaged_pages_by_visit = Hash.new { |hash, key| hash[key] = Set.new }
      engagement_rows.each do |visit_id, _time, page, _engaged_ms, _scroll_depth|
        next unless matcher.call(page.to_s)

        engaged_pages_by_visit[visit_id] << (Analytics::Urls.normalized_path_only(page).presence || page.to_s.presence || "(unknown)")
      end

      visits_by_pageview.each do |visit_id, events|
        next if events.empty?

        entry_visit_ids << visit_id if matcher.call(events.first.last)
        matched_pageviews += events.count { |_time, page| matcher.call(page) }
        next if events.length <= 1

        (0...(events.length - 1)).each do |index|
          time_a, page_a = events[index]
          time_b, page_b = events[index + 1]
          label = Analytics::Urls.normalized_path_only(page_a).presence || page_a.to_s.presence || "(unknown)"
          next unless matcher.call(page_a)
          next if Analytics::Urls.normalized_path_only(page_a) == Analytics::Urls.normalized_path_only(page_b)
          next if engaged_pages_by_visit[visit_id].include?(label)

          legacy_sum += [ (time_b - time_a).to_f, 0.0 ].max
          legacy_count += 1
        end
      end

      engagement_sum = 0.0
      engagement_visits = Set.new
      max_scroll_by_visit = {}

      engagement_rows.each do |visit_id, _time, page, engaged_ms, scroll_depth|
        next unless matcher.call(page.to_s)

        engagement_sum += (engaged_ms.to_f.positive? ? engaged_ms.to_f / 1000.0 : 0.0)
        engagement_visits << visit_id

        scroll_value = [ scroll_depth.to_f, 0.0 ].max
        current_scroll = max_scroll_by_visit[visit_id]
        max_scroll_by_visit[visit_id] = scroll_value if current_scroll.nil? || scroll_value > current_scroll
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

    def page_filter_matcher(query_or_filters, advanced_filters: [])
      query = normalize_query(query_or_filters, advanced_filters:)
      basic_filters = query.filters.to_h
      advanced_page_filters = query.advanced_filters.select { |_op, dim, _value| dim.to_s == "page" }

      lambda do |raw_page|
        page = raw_page.to_s
        normalized_page = Analytics::Urls.normalized_path_only(page).to_s

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

    def normalize_query(query_or_filters, advanced_filters: [])
      if query_or_filters.is_a?(Analytics::Query)
        query_or_filters
      else
        Analytics::Query.new(filters: query_or_filters, advanced_filters: advanced_filters)
      end
    end

    private
      def empty_page_filter_metrics
        {
          visitors: 0,
          visits: 0,
          pageviews: 0,
          bounce_rate: 0.0,
          time_on_page: 0.0,
          scroll_depth: 0.0
        }
      end
  end
end
