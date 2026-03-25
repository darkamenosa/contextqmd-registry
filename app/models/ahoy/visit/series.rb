module Ahoy::Visit::Series
  extend ActiveSupport::Concern

  class_methods do
    def main_graph_payload(query)
      metric = (query[:metric] || "visitors").to_s
      raw_range, interval = Ahoy::Visit.range_and_interval_for(query[:period], query[:interval], query)
      range = Ahoy::Visit.trim_range_to_now_if_applicable(raw_range, query[:period], comparison: query[:comparison])
      effective_source_range = Ahoy::Visit.trim_range_to_now_if_applicable(raw_range, query[:period])
      comparison_effective_range =
        if query[:period].to_s == "day"
          raw_range
        else
          effective_source_range
        end
      filters = query[:filters] || {}
      advanced_filters = query[:advanced_filters] || []

      series = series_for(range, interval, filters, metric, advanced_filters: advanced_filters)

      comparison = nil
      case query[:comparison]
      when "previous_period"
        prev_range = Ahoy::Visit.comparison_range_for(
          query,
          raw_range,
          effective_source_range: comparison_effective_range
        )
        comparison = series_for(prev_range, interval, filters, metric, advanced_filters: advanced_filters)
      when "year_over_year"
        prev_range = Ahoy::Visit.comparison_range_for(
          query,
          raw_range,
          effective_source_range: comparison_effective_range
        )
        comparison = series_for(prev_range, interval, filters, metric, advanced_filters: advanced_filters)
      when "custom"
        prev_range = Ahoy::Visit.comparison_range_for(
          query,
          raw_range,
          effective_source_range: comparison_effective_range
        )
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
        present_index: present_index_for(series[:labels], interval),
        interval: interval,
        full_intervals: full_intervals
      }
    end

    def series_for(range, interval, filters, metric, advanced_filters: [])
      bucket_sql = Ahoy::Visit.bucket_sql_for("started_at", interval)
      scope = Ahoy::Visit.scoped_visits(range, filters, advanced_filters: advanced_filters)

      if Ahoy::Visit.goal_filter_applied?(filters) && %w[visitors events conversion_rate].include?(metric.to_s)
        map = calculate_goal_metric_series(range, interval, filters, metric.to_s, advanced_filters: advanced_filters)
      elsif Ahoy::Visit.page_filter_applied?(filters, advanced_filters) &&
          %w[bounce_rate scroll_depth time_on_page].include?(metric.to_s)
        map = calculate_page_filter_metric_series(range, interval, filters, metric.to_s, advanced_filters: advanced_filters)
      elsif %w[views_per_visit bounce_rate visit_duration].include?(metric.to_s)
        map = calculate_complex_metric_series(range, interval, filters, metric.to_s, advanced_filters: advanced_filters)
      else
        grouped = case metric.to_s
        when "visitors"
          scope.group(Arel.sql(bucket_sql)).distinct.count(:visitor_token)
        when "pageviews"
          grouped_expression = Ahoy::Visit.bucket_sql_for("time", interval)
          Ahoy::Visit.scoped_events(range, filters, advanced_filters: advanced_filters).group(Arel.sql(grouped_expression)).count
        when "events"
          grouped_expression = Ahoy::Visit.bucket_sql_for("time", interval)
          Ahoy::Visit.goal_events_scope(range, filters, advanced_filters: advanced_filters).group(Arel.sql(grouped_expression)).count
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

    def calculate_complex_metric_series(range, interval, filters, metric, advanced_filters: [])
      bucket_sql = Ahoy::Visit.bucket_sql_for("started_at", interval)
      scope = Ahoy::Visit.scoped_visits(range, filters, advanced_filters: advanced_filters)
      events_scope = Ahoy::Visit.scoped_events(range, filters, advanced_filters: advanced_filters)

      visits_by_bucket = scope.group(Arel.sql(bucket_sql)).count
      result = {}

      visits_by_bucket.each do |bucket_time, _visit_count|
        key = bucket_time.is_a?(Time) ? bucket_time.utc : bucket_time.to_time.utc
        bucket_end = case interval
        when "month" then key + 1.month - 1.second
        when "week" then key + 1.week - 1.second
        when "day" then key + 1.day - 1.second
        when "hour" then key + 1.hour - 1.second
        when "minute" then key + 1.minute - 1.second
        else key + 1.hour - 1.second
        end
        bucket_range = key..[ bucket_end, range.end ].min

        bucket_visits = scope.where(started_at: bucket_range)
        visit_ids = bucket_visits.pluck(:id)
        next if visit_ids.empty?

        case metric
        when "views_per_visit"
          pageviews_per_visit = events_scope.where(visit_id: visit_ids).group(:visit_id).count
          pageviews = pageviews_per_visit.values.sum
          result[key] = visit_ids.size > 0 ? (pageviews.to_f / visit_ids.size.to_f).round(2) : 0.0

        when "bounce_rate"
          pageviews_per_visit = events_scope.where(visit_id: visit_ids).group(:visit_id).count
          non_pv_ids = Ahoy::Event
            .where(visit_id: visit_ids)
            .where.not(name: "pageview")
            .distinct
            .pluck(:visit_id)
            .to_set
          bounces = visit_ids.count { |vid| pageviews_per_visit[vid].to_i == 1 && !non_pv_ids.include?(vid) }
          result[key] = visit_ids.size > 0 ? ((bounces.to_f / visit_ids.size.to_f) * 100).round(2) : 0.0

        when "visit_duration"
          durations = events_scope
            .where(visit_id: visit_ids)
            .group(:visit_id)
            .pluck(Arel.sql("visit_id, GREATEST(EXTRACT(EPOCH FROM (MAX(time) - MIN(time))), 0) as duration"))
            .map { |_, duration| duration.to_f }

          result[key] = visit_ids.size > 0 ? (durations.sum / visit_ids.size.to_f).round(1) : 0.0
        end
      end

      result
    end

    def calculate_goal_metric_series(range, interval, filters, metric, advanced_filters: [])
      build_bucket_metric_series(range, interval) do |bucket_range|
        metrics = Ahoy::Visit.goal_metric_totals(bucket_range, filters, advanced_filters: advanced_filters)
        case metric
        when "visitors" then metrics[:unique_conversions]
        when "events" then metrics[:total_conversions]
        when "conversion_rate" then metrics[:conversion_rate]
        else 0
        end
      end
    end

    def calculate_page_filter_metric_series(range, interval, filters, metric, advanced_filters: [])
      build_bucket_metric_series(range, interval) do |bucket_range|
        metrics = Ahoy::Visit.page_filter_metrics(bucket_range, filters, advanced_filters: advanced_filters)
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
        bucket_key = bucket_start.utc
        result[bucket_key] = yield(bucket_start..bucket_end)
      end
      result
    end

    def each_bucket_range(range, interval)
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

      bucket_start = start_point
      while bucket_start <= range.end
        bucket_end = [ bucket_start + step - 1.second, range.end ].min
        yield(bucket_start, bucket_end)
        bucket_start += step
      end
    end
  end
end
