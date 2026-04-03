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
      return [] if goal_name.blank?

      base_query = query.without_goal
      visits = Analytics::VisitScope.visits(range, base_query)

      Analytics::FactStore.events(
        site: current_site,
        range: range,
        visit_ids: Analytics::FactStore.goal_event_visit_ids(
          site: current_site,
          range: range,
          visit_ids: visits.select(:id),
          goal_name: goal_name,
          goal: Analytics::Goals.configured(goal_name)
        )
      )
    end

    def goal_metric_totals(range, query_or_filters, advanced_filters: [])
      query = normalize_query(query_or_filters, advanced_filters:)
      goal_name = query.filter_value(:goal).presence
      base_query = query.without_goal
      visits = Analytics::VisitScope.visits(range, base_query)
      totals =
        if goal_name.present?
          Analytics::FactStore.goal_event_totals(
            site: current_site,
            range: range,
            visit_ids: visits.select(:id),
            goal_name: goal_name,
            goal: Analytics::Goals.configured(goal_name)
          )
        else
          { unique_conversions: 0, total_conversions: 0 }
        end

      total_visitors = Analytics::VisitScope
        .visits(range, query.without_goal_or_properties(property_filter: ->(key) { Analytics::Properties.filter_key?(key) }))
        .distinct
        .count(:visitor_token)

      conversion_rate =
        if total_visitors.positive?
          ((totals[:unique_conversions].to_f / total_visitors.to_f) * 100.0).round(2)
        else
          0.0
        end

      {
        unique_conversions: totals[:unique_conversions],
        total_conversions: totals[:total_conversions],
        conversion_rate: conversion_rate
      }
    end

    def visit_metrics(visits_scope, events_scope)
      total_visits = visits_scope.count
      live_visitors = Analytics::LiveState.current_visitors

      if (summary_metrics = visit_summary_metrics(visits_scope, total_visits))
        return {
          total_visits: total_visits,
          live_visitors: live_visitors,
          pageviews: summary_metrics[:pageviews],
          pageviews_per_visit: summary_metrics[:pageviews_per_visit],
          bounce_rate: summary_metrics[:bounce_rate],
          average_duration: summary_metrics[:average_duration]
        }
      end

      pageview_stats = grouped_pageview_stats(events_scope)

      pageviews = 0
      views_per_visit = 0.0
      bounce_rate = 0.0
      average_duration = 0.0

      if pageview_stats.any?
        pageviews = pageview_stats.values.sum { |stats| stats[:pageviews] }
        total_duration = pageview_stats.values.sum { |stats| stats[:duration] }
        views_per_visit = total_visits.zero? ? 0.0 : (pageviews.to_f / total_visits.to_f)
        average_duration = total_visits.zero? ? 0.0 : (total_duration.to_f / total_visits.to_f)
      else
        pageviews = total_visits
        views_per_visit = total_visits.zero? ? 0.0 : (pageviews.to_f / total_visits)
      end

      if total_visits.positive?
        bounces = bounce_count_for_scope(visits_scope, events_scope)
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

      if Analytics::VisitSummary.usable_for_visit_ids?(all_visit_ids)
        return grouped_summary_metrics(grouped_visit_ids)
      end

      pageview_stats = grouped_pageview_stats(events_scope.where(visit_id: all_visit_ids))
      non_pageview_ids = non_pageview_visit_ids(all_visit_ids)

      grouped_visit_ids.each_with_object({}) do |(name, visit_ids), result|
        denominator = visit_ids.size
        if denominator <= 0
          result[name] = { bounce_rate: nil, visit_duration: nil }
        else
          bounces = visit_ids.count do |visit_id|
            pageview_stats.fetch(visit_id, {}).fetch(:pageviews, 0) == 1 && !non_pageview_ids.include?(visit_id)
          end
          bounce_rate = (bounces.to_f / denominator.to_f * 100.0).round(2)
          average_duration = visit_ids.sum { |visit_id| pageview_stats.fetch(visit_id, {}).fetch(:duration, 0.0) } / denominator.to_f

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
      goal_visit_ids = Analytics::FactStore.goal_event_visit_ids(
        site: current_site,
        range: range,
        visit_ids: all_visit_ids,
        goal_name: goal_name,
        goal: Analytics::Goals.configured(goal_name)
      ).to_set

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

      if metrics = projected_page_filter_metrics(visits, visit_ids, query)
        return metrics
      end

      matcher = page_filter_matcher(query)
      pageview_rows = Analytics::FactStore.events(
        site: ::Analytics::Current.site_or_default,
        range: range,
        visit_ids: visit_ids,
        names: [ "pageview" ],
        order: :asc
      ).map do |event|
        [ event.visit_id, event.time, event.properties.to_h["page"].to_s ]
      end

      visits_by_pageview = Hash.new { |hash, key| hash[key] = [] }
      pageview_rows.each do |visit_id, time, page|
        visits_by_pageview[visit_id] << [ (time.respond_to?(:to_time) ? time.to_time : time), page.to_s ]
      end
      visits_by_pageview.each_value { |events| events.sort_by!(&:first) }

      matched_pageviews = 0
      legacy_sum = 0.0
      legacy_count = 0
      entry_visit_ids = []

      engagement_rows = Analytics::FactStore.events(
        site: ::Analytics::Current.site_or_default,
        range: range,
        visit_ids: visit_ids,
        names: [ "engagement" ],
        order: :asc
      ).map do |event|
        properties = event.properties.to_h
        [ event.visit_id, event.time, properties["page"].to_s, properties["engaged_ms"], properties["scroll_depth"] ]
      end

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

      entry_pageviews_by_visit = pageview_rows
        .select { |visit_id, *_rest| entry_visit_ids.include?(visit_id) }
        .group_by(&:first)
        .transform_values(&:count)
      non_pageview_visit_ids = Analytics::FactStore.non_pageview_visit_ids(
        site: ::Analytics::Current.site_or_default,
        visit_ids: entry_visit_ids
      )

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

    def projected_page_filter_metrics(visits, visit_ids, query)
      return unless Analytics::VisitPageEngagement.usable_for_visit_ids?(visit_ids)
      return unless visit_summary_usable_for_scope?(visits)

      page_metrics = apply_page_filter_relation(Analytics::VisitPageEngagement.where(visit_id: visit_ids), :page_path, query)
      return if page_metrics.none?

      entry_scope = apply_page_filter_relation(
        Analytics::VisitSummary.where(visit_id: visits.select(:id)).where.not(entry_page: ""),
        :entry_page,
        query
      )

      matched_pageviews = page_metrics.sum(:pageviews_count)
      legacy_sum = page_metrics.sum(:legacy_time_on_page_seconds)
      legacy_count = page_metrics.sum(:legacy_time_on_page_count)
      engagement_sum = page_metrics.sum(:engaged_seconds_total)
      engagement_visits = page_metrics.where(has_engagement: true).distinct.count(:visit_id)
      average_scroll = page_metrics.where(has_engagement: true).average(:max_scroll_depth)
      entry_visit_ids = entry_scope.pluck(:visit_id)
      single_pageview_ids = Analytics::VisitSummary.where(visit_id: entry_visit_ids, pageviews_count: 1).pluck(:visit_id)

      time_on_page_denominator = legacy_count.to_i + engagement_visits.to_i
      time_on_page =
        if time_on_page_denominator.positive?
          ((legacy_sum.to_f + engagement_sum.to_f) / time_on_page_denominator.to_f).round(1)
        else
          0.0
        end

      scroll_depth =
        if average_scroll.present?
          average_scroll.to_f.round(2)
        else
          0.0
        end

      bounces = Analytics::VisitSummary.where(
        visit_id: single_pageview_ids,
        has_non_pageview_events: false
      ).count
      bounce_rate =
        if entry_visit_ids.any?
          ((bounces.to_f / entry_visit_ids.size.to_f) * 100.0).round(2)
        else
          0.0
        end

      {
        visitors: visits.distinct.count(:visitor_token),
        visits: visits.count,
        pageviews: matched_pageviews.to_i,
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
      def bounce_count_for_scope(visits_scope, events_scope)
        visit_table = Ahoy::Visit.table_name
        pageview_table = events_scope.klass.table_name

        pageview_counts = events_scope
          .except(:select, :order)
          .select("#{pageview_table}.visit_id AS visit_id, COUNT(*) AS pageview_count")
          .group("#{pageview_table}.visit_id")

        visits_scope
          .joins("LEFT JOIN (#{pageview_counts.to_sql}) analytics_pageview_counts ON analytics_pageview_counts.visit_id = #{visit_table}.id")
          .where("COALESCE(analytics_pageview_counts.pageview_count, 0) = 1")
          .where.not(id: non_pageview_visit_ids(visits_scope.select(:id)).to_a)
          .count
      end

      def grouped_pageview_stats(events_scope)
        pageview_table = events_scope.klass.table_name

        events_scope
          .group("#{pageview_table}.visit_id")
          .pluck(
            Arel.sql("#{pageview_table}.visit_id"),
            Arel.sql("COUNT(*)"),
            Arel.sql(duration_sql("#{pageview_table}.time"))
          )
          .each_with_object({}) do |(visit_id, pageviews, duration), result|
            result[visit_id] = {
              pageviews: pageviews.to_i,
              duration: duration.to_f
            }
          end
      end

      def non_pageview_visit_ids(visit_ids_or_scope)
        Analytics::FactStore.non_pageview_visit_ids(site: current_site, visit_ids: visit_ids_or_scope)
      end

      def visit_summary_metrics(visits_scope, total_visits)
        return if total_visits.zero?
        return unless visit_summary_usable_for_scope?(visits_scope)

        summaries = Analytics::VisitSummary.where(visit_id: visits_scope.select(:id))
        total_pageviews = summaries.sum(:pageviews_count).to_i
        total_duration = summaries.sum(:visit_duration_seconds).to_f
        bounces = summaries.where(pageviews_count: 1, has_non_pageview_events: false).count
        pageviews = total_pageviews.positive? ? total_pageviews : total_visits

        {
          pageviews: pageviews,
          pageviews_per_visit: pageviews.to_f / total_visits.to_f,
          bounce_rate: (bounces.to_f / total_visits.to_f * 100.0),
          average_duration: total_duration / total_visits.to_f
        }
      end

      def grouped_summary_metrics(grouped_visit_ids)
        summary_by_visit_id = Analytics::VisitSummary
          .where(visit_id: grouped_visit_ids.values.flatten)
          .pluck(:visit_id, :pageviews_count, :visit_duration_seconds, :has_non_pageview_events)
          .each_with_object({}) do |(visit_id, pageviews_count, duration_seconds, has_non_pageview_events), result|
            result[visit_id] = {
              pageviews_count: pageviews_count.to_i,
              visit_duration_seconds: duration_seconds.to_f,
              has_non_pageview_events: has_non_pageview_events
            }
          end

        grouped_visit_ids.each_with_object({}) do |(name, visit_ids), result|
          denominator = visit_ids.size

          if denominator <= 0
            result[name] = { bounce_rate: nil, visit_duration: nil }
          else
            bounces = visit_ids.count do |visit_id|
              summary = summary_by_visit_id[visit_id]
              summary && summary[:pageviews_count] == 1 && !summary[:has_non_pageview_events]
            end
            average_duration = visit_ids.sum do |visit_id|
              summary_by_visit_id.fetch(visit_id, {}).fetch(:visit_duration_seconds, 0.0)
            end / denominator.to_f

            result[name] = {
              bounce_rate: (bounces.to_f / denominator.to_f * 100.0).round(2),
              visit_duration: average_duration.round(1)
            }
          end
        end
      end

      def apply_page_filter_relation(relation, column, query)
        if (page_value = normalized_page_filter(query.filter_value(:page))).present?
          relation = relation.where(column => page_value)
        end

        query.advanced_filters.each do |operator, dimension, value|
          next unless dimension.to_s == "page"

          case operator
          when "contains"
            relation = relation.where(page_column_matches(relation, column, Analytics::Search.contains_pattern(value)))
          when "is_not"
            if (page_value = normalized_page_filter(value)).present?
              relation = relation.where.not(column => page_value)
            end
          end
        end

        relation
      end

      def page_column_matches(relation, column, pattern)
        Arel::Nodes::NamedFunction.new("LOWER", [ relation.klass.arel_table[column.to_sym] ]).matches(pattern)
      end

      def normalized_page_filter(value)
        return if value.blank?

        normalized = Analytics::Urls.normalized_path_only(value).presence
        normalized || value.to_s.strip
      end

      def visit_summary_usable_for_scope?(visits_scope)
        Analytics::VisitSummary.usable_for_scope?(visits_scope)
      rescue StandardError
        false
      end

      def current_site
        ::Analytics::Current.site_or_default
      end

      def duration_sql(column)
        "GREATEST(EXTRACT(EPOCH FROM (MAX(#{column}) - MIN(#{column}))), 0)"
      end

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
