# frozen_string_literal: true

class Analytics::TimeSeries
  class << self
    def series_for(range, interval, query_or_filters, metric, advanced_filters: [])
      query = normalize_query(query_or_filters, advanced_filters:)

      map =
        if (rollup_map = site_hourly_rollup_series(range:, interval:, query:, metric: metric.to_s))
          rollup_map
        elsif query.goal_filter_applied? && %w[visitors events conversion_rate].include?(metric.to_s)
          calculate_goal_metric_series(range, interval, query, metric.to_s)
        elsif query.page_filter_applied? && %w[bounce_rate scroll_depth time_on_page].include?(metric.to_s)
          calculate_page_filter_metric_series(range, interval, query, metric.to_s)
        elsif %w[views_per_visit bounce_rate visit_duration].include?(metric.to_s)
          calculate_complex_metric_series(range, interval, query, metric.to_s)
        else
          bucket_sql = Analytics::Ranges.bucket_sql_for("started_at", interval)
          visits = Analytics::VisitScope.visits(range, query)
          grouped = case metric.to_s
          when "visitors"
            visits.group(Arel.sql(bucket_sql)).distinct.count(:visitor_token)
          when "pageviews"
            grouped_expression = Analytics::Ranges.bucket_sql_for("time", interval)
            Analytics::VisitScope.pageviews(range, query).group(Arel.sql(grouped_expression)).count
          when "events"
            Analytics::FactStore.goal_event_bucket_counts(
              site: current_site,
              range: range,
              visit_ids: visits.select(:id),
              goal_name: query.filter_value(:goal).presence,
              goal: Analytics::Goals.configured(query.filter_value(:goal).presence),
              interval: interval
            )
          else
            visits.group(Arel.sql(bucket_sql)).count
          end

          grouped.each_with_object({}) do |(time, value), result|
            key = time.is_a?(Time) ? time.utc : time.to_time.utc
            result[key] = value.to_i
          end
        end

      labels = []
      values = []
      bucket_start = bucket_start_for(range, interval)
      step = step_for(interval)

      while bucket_start <= range.end
        key = bucket_start.utc
        labels << key.iso8601
        values << (map[key] || 0)
        bucket_start += step
      end

      { values: values, labels: labels }
    end

    def present_index_for(labels, interval)
      current_label = current_bucket_label_for(interval)
      return nil unless current_label

      labels.index(current_label)
    end

    def current_bucket_label_for(interval)
      current_time = Time.zone.now

      bucket_start = case interval.to_s
      when "minute"
        current_time.beginning_of_minute
      when "hour"
        current_time.beginning_of_hour
      when "day"
        current_time.beginning_of_day
      when "week"
        current_time.beginning_of_week
      when "month"
        current_time.beginning_of_month
      end

      bucket_start&.utc&.iso8601
    end

    def calculate_complex_metric_series(range, interval, query_or_filters, metric, advanced_filters: [])
      query = normalize_query(query_or_filters, advanced_filters:)
      visits = Analytics::VisitScope.visits(range, query)
      return {} if visits.none?

      if Analytics::VisitSummary.usable_for_scope?(visits)
        return complex_metric_series_from_summaries(visits, interval, metric)
      end

      bucket_sql = Analytics::Ranges.bucket_sql_for("started_at", interval)
      visits_by_bucket = visits.group(Arel.sql(bucket_sql)).count.each_with_object({}) do |(bucket_time, count), result|
        result[normalize_bucket_time(bucket_time)] = count.to_i
      end
      return {} if visits_by_bucket.empty?

      visit_ids = visits.pluck(:id)
      visit_bucket_by_id = visits.pluck(:id, Arel.sql(bucket_sql)).to_h do |visit_id, bucket_time|
        [ visit_id, normalize_bucket_time(bucket_time) ]
      end
      pageview_rows = Analytics::FactStore.events(
        site: current_site,
        range: range,
        visit_ids: visit_ids,
        names: [ "pageview" ],
        order: :asc
      )
      pageviews_by_bucket = Hash.new(0)
      durations_by_bucket = Hash.new(0.0)
      bounces_by_bucket = Hash.new(0)
      non_pageview_ids = Analytics::FactStore.non_pageview_visit_ids(site: current_site, visit_ids: visit_ids)

      pageview_rows.group_by(&:visit_id).each do |visit_id, rows|
        key = visit_bucket_by_id[visit_id]
        next if key.blank?

        ordered_rows = rows.sort_by { |event| [ event.time || Time.at(0), event.id.to_i ] }
        pageview_count = ordered_rows.length
        duration =
          if ordered_rows.length > 1
            [ (ordered_rows.last.time.to_time - ordered_rows.first.time.to_time).to_f, 0.0 ].max
          else
            0.0
          end

        pageviews_by_bucket[key] += pageview_count
        durations_by_bucket[key] += duration
        bounces_by_bucket[key] += 1 if pageview_count == 1 && !non_pageview_ids.include?(visit_id)
      end

      visits_by_bucket.each_with_object({}) do |(key, denominator), result|
        result[key] =
          case metric
          when "views_per_visit"
            denominator.positive? ? (pageviews_by_bucket[key].to_f / denominator.to_f).round(2) : 0.0
          when "bounce_rate"
            denominator.positive? ? ((bounces_by_bucket[key].to_f / denominator.to_f) * 100).round(2) : 0.0
          when "visit_duration"
            denominator.positive? ? (durations_by_bucket[key].to_f / denominator.to_f).round(1) : 0.0
          end
      end
    end

    def calculate_goal_metric_series(range, interval, query_or_filters, metric, advanced_filters: [])
      query = normalize_query(query_or_filters, advanced_filters:)
      build_bucket_metric_series(range, interval) do |bucket_range|
        metrics = Analytics::ReportMetrics.goal_metric_totals(bucket_range, query)
        case metric
        when "visitors" then metrics[:unique_conversions]
        when "events" then metrics[:total_conversions]
        when "conversion_rate" then metrics[:conversion_rate]
        else 0
        end
      end
    end

    def calculate_page_filter_metric_series(range, interval, query_or_filters, metric, advanced_filters: [])
      query = normalize_query(query_or_filters, advanced_filters:)
      build_bucket_metric_series(range, interval) do |bucket_range|
        metrics = Analytics::ReportMetrics.page_filter_metrics(bucket_range, query)
        case metric
        when "bounce_rate" then metrics[:bounce_rate]
        when "scroll_depth" then metrics[:scroll_depth]
        when "time_on_page" then metrics[:time_on_page]
        else 0
        end
      end
    end

    def build_bucket_metric_series(range, interval)
      result = {}
      each_bucket_range(range, interval) do |bucket_start, bucket_end|
        result[bucket_start.utc] = yield(bucket_start..bucket_end)
      end
      result
    end

    def each_bucket_range(range, interval)
      bucket_start = bucket_start_for(range, interval)
      step = step_for(interval)

      while bucket_start <= range.end
        bucket_end = [ bucket_start + step - 1.second, range.end ].min
        yield(bucket_start, bucket_end)
        bucket_start += step
      end
    end

    private
      def site_hourly_rollup_series(range:, interval:, query:, metric:)
        return nil unless query.filter_clauses.empty?
        return nil if interval.to_s == "minute"

        case metric
        when "visits"
          return nil unless Analytics::SiteVisitHourlyRollup.usable_for?(range:, site: current_site)

          Analytics::SiteVisitHourlyRollup.series_for(range:, interval:, site: current_site, column: :visits_count)
        when "pageviews"
          return nil unless Analytics::SiteEventHourlyRollup.usable_for?(range:, site: current_site)

          Analytics::SiteEventHourlyRollup.series_for(range:, interval:, site: current_site, column: :pageviews_count)
        when "events"
          return nil unless Analytics::SiteEventHourlyRollup.usable_for?(range:, site: current_site)

          Analytics::SiteEventHourlyRollup.series_for(range:, interval:, site: current_site, column: :events_count)
        when "views_per_visit", "bounce_rate", "visit_duration"
          return nil unless Analytics::SiteVisitHourlyRollup.complex_metrics_usable_for?(range:, site: current_site)

          Analytics::SiteVisitHourlyRollup.complex_metric_series(range:, interval:, site: current_site, metric:)
        end
      end

      def complex_metric_series_from_summaries(visits_scope, interval, metric)
        bucket_sql = Analytics::Ranges.bucket_sql_for("#{Analytics::VisitSummary.table_name}.started_at", interval)

        Analytics::VisitSummary
          .where(visit_id: visits_scope.select(:id))
          .group(Arel.sql(bucket_sql))
          .pluck(
            Arel.sql(bucket_sql),
            Arel.sql("COUNT(*)"),
            Arel.sql("COALESCE(SUM(pageviews_count), 0)"),
            Arel.sql("COUNT(*) FILTER (WHERE pageviews_count = 1 AND has_non_pageview_events = FALSE)"),
            Arel.sql("COALESCE(SUM(visit_duration_seconds), 0)")
          )
          .each_with_object({}) do |(bucket_time, visits_count, pageviews_count, bounces_count, total_duration), result|
            key = normalize_bucket_time(bucket_time)
            denominator = visits_count.to_i

            result[key] =
              case metric
              when "views_per_visit"
                denominator.positive? ? (pageviews_count.to_f / denominator.to_f).round(2) : 0.0
              when "bounce_rate"
                denominator.positive? ? ((bounces_count.to_f / denominator.to_f) * 100.0).round(2) : 0.0
              when "visit_duration"
                denominator.positive? ? (total_duration.to_f / denominator.to_f).round(1) : 0.0
              end
          end
      end

      def current_site
        ::Analytics::Current.site_or_default
      end

      def normalize_bucket_time(bucket_time)
        bucket_time.is_a?(Time) ? bucket_time.utc : bucket_time.to_time.utc
      end

      def normalize_query(query_or_filters, advanced_filters: [])
        if query_or_filters.is_a?(Analytics::Query)
          query_or_filters
        else
          Analytics::Query.new(filters: query_or_filters, advanced_filters: advanced_filters)
        end
      end

      def bucket_start_for(range, interval)
        case interval
        when "month" then range.begin.beginning_of_month
        when "week" then range.begin.beginning_of_week
        when "day" then range.begin.beginning_of_day
        when "hour" then range.begin.beginning_of_hour
        when "minute" then range.begin.beginning_of_minute
        else range.begin.beginning_of_hour
        end
      end

      def step_for(interval)
        case interval
        when "month" then 1.month
        when "week" then 1.week
        when "day" then 1.day
        when "hour" then 1.hour
        when "minute" then 1.minute
        else 1.hour
        end
      end
  end
end
