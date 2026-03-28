# frozen_string_literal: true

class Analytics::TopStatsQuery::Postgres
  def initialize(query:)
    @query = Analytics::Query.wrap(query)
  end

  def payload
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
      comparing_from: previous_range.begin.iso8601,
      comparing_to: previous_range.end.iso8601
    }
  end

  private
    attr_reader :query

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
      @range ||= Analytics::Ranges.trim_range_to_now_if_applicable(raw_range, query.time_range_key)
    end

    def previous_range
      @previous_range ||= Analytics::Ranges.comparison_range_for(query, raw_range, effective_source_range: range) || Analytics::Ranges.previous_range(range)
    end

    def stats
      @stats ||= begin
        rows = [ { name: "Live visitors", value: Analytics::LiveState.current_visitors, graph_metric: :currentVisitors, change: nil, comparison_value: nil } ]
        rows.concat(metric_rows)
      end
    end

    def graphable_metrics
      @graphable_metrics ||= begin
        if query.goal_filter_applied?
          %w[visitors events conversion_rate]
        elsif query.page_filter_applied?
          %w[visitors visits pageviews bounce_rate scroll_depth time_on_page]
        else
          %w[visitors visits pageviews views_per_visit bounce_rate visit_duration]
        end
      end
    end

    def metric_rows
      if query.goal_filter_applied?
        goal_metric_rows
      elsif query.page_filter_applied?
        page_metric_rows
      else
        visit_metric_rows
      end
    end

    def goal_metric_rows
      metrics = Analytics::ReportMetrics.goal_metric_totals(range, query)
      previous_metrics = Analytics::ReportMetrics.goal_metric_totals(previous_range, query)

      [
        {
          name: "Unique conversions",
          value: metrics[:unique_conversions],
          graph_metric: :visitors,
          change: Analytics::ReportMetrics.top_stat_change(:visitors, previous_metrics[:unique_conversions], metrics[:unique_conversions]),
          comparison_value: previous_metrics[:unique_conversions]
        },
        {
          name: "Total conversions",
          value: metrics[:total_conversions],
          graph_metric: :events,
          change: Analytics::ReportMetrics.top_stat_change(:events, previous_metrics[:total_conversions], metrics[:total_conversions]),
          comparison_value: previous_metrics[:total_conversions]
        },
        {
          name: "Conversion rate",
          value: metrics[:conversion_rate],
          graph_metric: :conversion_rate,
          change: Analytics::ReportMetrics.top_stat_change(:conversion_rate, previous_metrics[:conversion_rate], metrics[:conversion_rate]),
          comparison_value: previous_metrics[:conversion_rate]
        }
      ]
    end

    def page_metric_rows
      current_visits = Analytics::VisitScope.visits(range, query)
      current_events = Analytics::VisitScope.pageviews(range, query)
      current_metrics = Analytics::ReportMetrics.visit_metrics(current_visits, current_events)
      previous_visits = Analytics::VisitScope.visits(previous_range, query)
      previous_events = Analytics::VisitScope.pageviews(previous_range, query)
      previous_metrics = Analytics::ReportMetrics.visit_metrics(previous_visits, previous_events)
      uniques = current_visits.select(:visitor_token).distinct.count
      previous_uniques = previous_visits.select(:visitor_token).distinct.count
      page_metrics = Analytics::ReportMetrics.page_filter_metrics(range, query)
      previous_page_metrics = Analytics::ReportMetrics.page_filter_metrics(previous_range, query)

      [
        {
          name: "Unique visitors",
          value: uniques,
          graph_metric: :visitors,
          change: Analytics::ReportMetrics.top_stat_change(:visitors, previous_uniques, uniques),
          comparison_value: previous_uniques
        },
        {
          name: "Total visits",
          value: current_metrics[:total_visits],
          graph_metric: :visits,
          change: Analytics::ReportMetrics.top_stat_change(:visits, previous_metrics[:total_visits], current_metrics[:total_visits]),
          comparison_value: previous_metrics[:total_visits]
        },
        {
          name: "Total pageviews",
          value: current_metrics[:pageviews],
          graph_metric: :pageviews,
          change: Analytics::ReportMetrics.top_stat_change(:pageviews, previous_metrics[:pageviews], current_metrics[:pageviews]),
          comparison_value: previous_metrics[:pageviews]
        },
        {
          name: "Bounce rate",
          value: page_metrics[:bounce_rate],
          graph_metric: :bounce_rate,
          change: Analytics::ReportMetrics.top_stat_change(:bounce_rate, previous_page_metrics[:bounce_rate], page_metrics[:bounce_rate]),
          comparison_value: previous_page_metrics[:bounce_rate]
        },
        {
          name: "Scroll depth",
          value: page_metrics[:scroll_depth],
          graph_metric: :scroll_depth,
          change: Analytics::ReportMetrics.top_stat_change(:scroll_depth, previous_page_metrics[:scroll_depth], page_metrics[:scroll_depth]),
          comparison_value: previous_page_metrics[:scroll_depth]
        },
        {
          name: "Time on page",
          value: page_metrics[:time_on_page],
          graph_metric: :time_on_page,
          change: Analytics::ReportMetrics.top_stat_change(:time_on_page, previous_page_metrics[:time_on_page], page_metrics[:time_on_page]),
          comparison_value: previous_page_metrics[:time_on_page]
        }
      ]
    end

    def visit_metric_rows
      current_visits = Analytics::VisitScope.visits(range, query)
      current_events = Analytics::VisitScope.pageviews(range, query)
      current_metrics = Analytics::ReportMetrics.visit_metrics(current_visits, current_events)
      previous_visits = Analytics::VisitScope.visits(previous_range, query)
      previous_events = Analytics::VisitScope.pageviews(previous_range, query)
      previous_metrics = Analytics::ReportMetrics.visit_metrics(previous_visits, previous_events)
      uniques = current_visits.select(:visitor_token).distinct.count
      previous_uniques = previous_visits.select(:visitor_token).distinct.count

      [
        {
          name: "Unique visitors",
          value: uniques,
          graph_metric: :visitors,
          change: Analytics::ReportMetrics.top_stat_change(:visitors, previous_uniques, uniques),
          comparison_value: previous_uniques
        },
        {
          name: "Total visits",
          value: current_metrics[:total_visits],
          graph_metric: :visits,
          change: Analytics::ReportMetrics.top_stat_change(:visits, previous_metrics[:total_visits], current_metrics[:total_visits]),
          comparison_value: previous_metrics[:total_visits]
        },
        {
          name: "Total pageviews",
          value: current_metrics[:pageviews],
          graph_metric: :pageviews,
          change: Analytics::ReportMetrics.top_stat_change(:pageviews, previous_metrics[:pageviews], current_metrics[:pageviews]),
          comparison_value: previous_metrics[:pageviews]
        },
        {
          name: "Views per visit",
          value: current_metrics[:pageviews_per_visit].round(2),
          graph_metric: :views_per_visit,
          change: Analytics::ReportMetrics.top_stat_change(:views_per_visit, previous_metrics[:pageviews_per_visit], current_metrics[:pageviews_per_visit]),
          comparison_value: previous_metrics[:pageviews_per_visit]
        },
        {
          name: "Bounce rate",
          value: current_metrics[:bounce_rate].round(2),
          graph_metric: :bounce_rate,
          change: Analytics::ReportMetrics.top_stat_change(:bounce_rate, previous_metrics[:bounce_rate], current_metrics[:bounce_rate]),
          comparison_value: previous_metrics[:bounce_rate]
        },
        {
          name: "Visit duration",
          value: current_metrics[:average_duration].round(1),
          graph_metric: :visit_duration,
          change: Analytics::ReportMetrics.top_stat_change(:visit_duration, previous_metrics[:average_duration], current_metrics[:average_duration]),
          comparison_value: previous_metrics[:average_duration]
        }
      ]
    end
end
