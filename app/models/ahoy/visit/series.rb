module Ahoy::Visit::Series
  extend ActiveSupport::Concern

  class_methods do
    def main_graph_payload(query)
      metric = (query[:metric] || "visitors").to_s
      range, interval = Ahoy::Visit.range_and_interval_for(query[:period], query[:interval], query)
      range = Ahoy::Visit.trim_range_to_now_if_applicable(range, query[:period], comparison: query[:comparison])
      filters = query[:filters] || {}
      advanced_filters = query[:advanced_filters] || []

      series = series_for(range, interval, filters, metric, advanced_filters: advanced_filters)

      comparison = nil
      case query[:comparison]
      when "previous_period"
        prev_range = Ahoy::Visit.previous_range(range)
        if ActiveModel::Type::Boolean.new.cast(query[:match_day_of_week])
          prev_range = Ahoy::Visit.align_comparison_weekday(prev_range, range)
        end
        comparison = series_for(prev_range, interval, filters, metric, advanced_filters: advanced_filters)
      when "year_over_year"
        prev_range = Ahoy::Visit.year_over_year_range(range)
        if ActiveModel::Type::Boolean.new.cast(query[:match_day_of_week])
          prev_range = Ahoy::Visit.align_comparison_weekday(prev_range, range)
        end
        comparison = series_for(prev_range, interval, filters, metric, advanced_filters: advanced_filters)
      when "custom"
        prev_range = Ahoy::Visit.custom_compare_range(query)
        comparison = prev_range ? series_for(prev_range, interval, filters, metric, advanced_filters: advanced_filters) : nil
      end

      full_intervals = case interval
      when "week"
        date_range = (range.begin.to_date..range.end.to_date)
        series[:labels].each_with_object({}) do |label, acc|
          begin
            d = Date.parse(label)
            start = d.beginning_of_week
            finish = d.end_of_week
            acc[label] = date_range.cover?(start) && date_range.cover?(finish)
          rescue ArgumentError
            acc[label] = false
          end
        end
      when "month"
        date_range = (range.begin.to_date..range.end.to_date)
        series[:labels].each_with_object({}) do |label, acc|
          begin
            d = Date.parse(label)
            start = d.beginning_of_month
            finish = d.end_of_month
            acc[label] = date_range.cover?(start) && date_range.cover?(finish)
          rescue ArgumentError
            acc[label] = false
          end
        end
      else
        nil
      end

      {
        metric: metric,
        plot: series[:values],
        labels: series[:labels],
        comparison_plot: comparison && comparison[:values],
        comparison_labels: comparison && comparison[:labels],
        present_index: series[:labels].length - 1,
        interval: interval,
        full_intervals: full_intervals
      }
    end

    def series_for(range, interval, filters, metric, advanced_filters: [])
      bucket_sql = Ahoy::Visit.bucket_sql_for("started_at", interval)
      scope = Ahoy::Visit.scoped_visits(range, filters, advanced_filters: advanced_filters)

      if %w[views_per_visit bounce_rate visit_duration].include?(metric.to_s)
        map = calculate_complex_metric_series(range, interval, filters, metric.to_s, advanced_filters: advanced_filters)
      else
        grouped = case metric.to_s
        when "visitors"
          scope.group(Arel.sql(bucket_sql)).distinct.count(:visitor_token)
        when "pageviews"
          grouped_expression = Ahoy::Visit.bucket_sql_for("time", interval)
          Ahoy::Visit.scoped_events(range, filters, advanced_filters: advanced_filters).group(Arel.sql(grouped_expression)).count
        else # visits
          scope.group(Arel.sql(bucket_sql)).count
        end

        map = grouped.each_with_object({}) do |(ts, v), h|
          key = ts.is_a?(Time) ? ts.utc : ts.to_time.utc
          h[key] = v.to_i
        end
      end

      start_point = case interval
      when "month" then range.begin.beginning_of_month
      when "week" then range.begin.beginning_of_week
      when "day" then range.begin.beginning_of_day
      when "hour" then range.begin.beginning_of_hour
      when "minute" then range.begin.beginning_of_minute
      else range.begin.beginning_of_hour
      end
      step = case interval
      when "month" then 1.month
      when "week" then 1.week
      when "day" then 1.day
      when "hour" then 1.hour
      when "minute" then 1.minute
      else 1.hour
      end
      labels = []
      values = []
      t = start_point
      while t <= range.end
        key = t.utc
        labels << key.iso8601
        values << (map[key] || 0)
        t += step
      end

      { values: values, labels: labels }
    end

    def calculate_complex_metric_series(range, interval, filters, metric, advanced_filters: [])
      bucket_sql = Ahoy::Visit.bucket_sql_for("started_at", interval)
      scope = Ahoy::Visit.scoped_visits(range, filters, advanced_filters: advanced_filters)
      events_scope = Ahoy::Visit.scoped_events(range, filters, advanced_filters: advanced_filters)

      visits_by_bucket = scope.group(Arel.sql(bucket_sql)).count
      result = {}

      visits_by_bucket.each do |bucket_time, _visit_count|
        key = bucket_time.is_a?(Time) ? bucket_time.utc : bucket_time.to_time.utc
        bucket_range = case interval
        when "month" then key..(key + 1.month)
        when "week" then key..(key + 1.week)
        when "day" then key..(key + 1.day)
        when "hour" then key..(key + 1.hour)
        when "minute" then key..(key + 1.minute)
        else key..(key + 1.hour)
        end

        bucket_visits = scope.where(started_at: bucket_range)
        visit_ids = bucket_visits.pluck(:id)
        next if visit_ids.empty?

        case metric
        when "views_per_visit"
          pageviews_per_visit = events_scope.where(visit_id: visit_ids).group(:visit_id).count
          pageviews = pageviews_per_visit.values.sum
          v_with_events = pageviews_per_visit.size
          result[key] = v_with_events > 0 ? (pageviews.to_f / v_with_events).round(2) : 0.0

        when "bounce_rate"
          pageviews_per_visit = events_scope.where(visit_id: visit_ids).group(:visit_id).count
          v_with_events = pageviews_per_visit.size
          bounces = pageviews_per_visit.count { |_, cnt| cnt == 1 }
          result[key] = v_with_events > 0 ? ((bounces.to_f / v_with_events) * 100).round(2) : 0.0

        when "visit_duration"
          durations = events_scope
            .where(visit_id: visit_ids)
            .group(:visit_id)
            .pluck(Arel.sql("visit_id, GREATEST(EXTRACT(EPOCH FROM (MAX(time) - MIN(time))), 0) as duration"))
            .map { |_, duration| duration.to_f }

          v_with_events = durations.size
          result[key] = v_with_events > 0 ? (durations.sum / v_with_events).round(1) : 0.0
        end
      end

      result
    end
  end
end
