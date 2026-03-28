# frozen_string_literal: true

class Analytics::TimeSeries
  class << self
    def series_for(range, interval, query_or_filters, metric, advanced_filters: [])
      query = normalize_query(query_or_filters, advanced_filters:)
      bucket_sql = Analytics::Ranges.bucket_sql_for("started_at", interval)
      visits = Analytics::VisitScope.visits(range, query)

      map =
        if query.goal_filter_applied? && %w[visitors events conversion_rate].include?(metric.to_s)
          calculate_goal_metric_series(range, interval, query, metric.to_s)
        elsif query.page_filter_applied? && %w[bounce_rate scroll_depth time_on_page].include?(metric.to_s)
          calculate_page_filter_metric_series(range, interval, query, metric.to_s)
        elsif %w[views_per_visit bounce_rate visit_duration].include?(metric.to_s)
          calculate_complex_metric_series(range, interval, query, metric.to_s)
        else
          grouped = case metric.to_s
          when "visitors"
            visits.group(Arel.sql(bucket_sql)).distinct.count(:visitor_token)
          when "pageviews"
            grouped_expression = Analytics::Ranges.bucket_sql_for("time", interval)
            Analytics::VisitScope.pageviews(range, query).group(Arel.sql(grouped_expression)).count
          when "events"
            grouped_expression = Analytics::Ranges.bucket_sql_for("time", interval)
            Analytics::ReportMetrics.goal_events_scope(range, query).group(Arel.sql(grouped_expression)).count
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
      bucket_sql = Analytics::Ranges.bucket_sql_for("started_at", interval)
      visits = Analytics::VisitScope.visits(range, query)
      events = Analytics::VisitScope.pageviews(range, query)
      visits_by_bucket = visits.group(Arel.sql(bucket_sql)).count

      visits_by_bucket.each_with_object({}) do |(bucket_time, _), result|
        key = bucket_time.is_a?(Time) ? bucket_time.utc : bucket_time.to_time.utc
        bucket_end = [ key + step_for(interval) - 1.second, range.end ].min
        bucket_range = key..bucket_end
        bucket_visits = visits.where(started_at: bucket_range)
        visit_ids = bucket_visits.pluck(:id)
        next if visit_ids.empty?

        result[key] =
          case metric
          when "views_per_visit"
            pageviews_by_visit = events.where(visit_id: visit_ids).group(:visit_id).count
            pageviews = pageviews_by_visit.values.sum
            visit_ids.size > 0 ? (pageviews.to_f / visit_ids.size.to_f).round(2) : 0.0
          when "bounce_rate"
            pageviews_by_visit = events.where(visit_id: visit_ids).group(:visit_id).count
            non_pageview_ids = Ahoy::Event
              .where(visit_id: visit_ids)
              .where.not(name: "pageview")
              .distinct
              .pluck(:visit_id)
              .to_set
            bounces = visit_ids.count { |visit_id| pageviews_by_visit[visit_id].to_i == 1 && !non_pageview_ids.include?(visit_id) }
            visit_ids.size > 0 ? ((bounces.to_f / visit_ids.size.to_f) * 100).round(2) : 0.0
          when "visit_duration"
            durations = events
              .where(visit_id: visit_ids)
              .group(:visit_id)
              .pluck(Arel.sql("visit_id, GREATEST(EXTRACT(EPOCH FROM (MAX(time) - MIN(time))), 0) as duration"))
              .map { |_, duration| duration.to_f }
            visit_ids.size > 0 ? (durations.sum / visit_ids.size.to_f).round(1) : 0.0
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
