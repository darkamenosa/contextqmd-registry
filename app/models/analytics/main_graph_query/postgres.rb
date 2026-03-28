# frozen_string_literal: true

class Analytics::MainGraphQuery::Postgres
  def initialize(query:)
    @query = Analytics::Query.wrap(query)
  end

  def payload
    {
      metric: metric,
      plot: series[:values],
      labels: series[:labels],
      comparison_plot: comparison_series && comparison_series[:values],
      comparison_labels: comparison_series && comparison_series[:labels],
      present_index: Analytics::TimeSeries.present_index_for(series[:labels], interval),
      interval: interval,
      full_intervals: full_intervals
    }
  end

  private
    attr_reader :query

    def metric
      @metric ||= (query.metric || "visitors").to_s
    end

    def raw_range_and_interval
      @raw_range_and_interval ||= Analytics::Ranges.range_and_interval_for(query.time_range_key, query.interval, query)
    end

    def raw_range
      raw_range_and_interval.first
    end

    def interval
      raw_range_and_interval.last
    end

    def range
      @range ||= Analytics::Ranges.trim_range_to_now_if_applicable(raw_range, query.time_range_key, comparison: query.comparison)
    end

    def effective_source_range
      @effective_source_range ||= Analytics::Ranges.trim_range_to_now_if_applicable(raw_range, query.time_range_key)
    end

    def comparison_effective_range
      query.time_range_key.to_s == "day" ? raw_range : effective_source_range
    end

    def series
      @series ||= Analytics::TimeSeries.series_for(range, interval, query, metric)
    end

    def comparison_series
      @comparison_series ||= begin
        previous_range =
          case query.comparison
          when "previous_period", "year_over_year", "custom"
            Analytics::Ranges.comparison_range_for(
              query,
              raw_range,
              effective_source_range: comparison_effective_range
            )
          end

        previous_range ? Analytics::TimeSeries.series_for(previous_range, interval, query, metric) : nil
      end
    end

    def full_intervals
      case interval
      when "week"
        date_range = (range.begin.to_date..range.end.to_date)
        series[:labels].each_with_object({}) do |label, result|
          begin
            date = Date.parse(label)
            start_date = date.beginning_of_week
            end_date = date.end_of_week
            result[label] = date_range.cover?(start_date) && date_range.cover?(end_date)
          rescue ArgumentError
            result[label] = false
          end
        end
      when "month"
        date_range = (range.begin.to_date..range.end.to_date)
        series[:labels].each_with_object({}) do |label, result|
          begin
            date = Date.parse(label)
            start_date = date.beginning_of_month
            end_date = date.end_of_month
            result[label] = date_range.cover?(start_date) && date_range.cover?(end_date)
          rescue ArgumentError
            result[label] = false
          end
        end
      else
        nil
      end
    end
end
