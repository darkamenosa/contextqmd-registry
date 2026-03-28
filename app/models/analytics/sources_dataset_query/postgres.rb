# frozen_string_literal: true

class Analytics::SourcesDatasetQuery::Postgres
  def initialize(query:, limit:, page:, search:, order_by:)
    @query = Analytics::Query.wrap(query)
    @limit = limit
    @page = page
    @search = search
    @order_by = order_by
  end

  def payload
    return full_payload unless paged?

    grouped_visit_ids = paged_grouped_visit_ids
    counts = Analytics::ReportMetrics.unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits)
    remove_empty_utm_groups!(grouped_visit_ids, counts) if utm_mode?
    Analytics::Sources.filter_groups!(mode, grouped_visit_ids, counts, comparison_names)
    total = Analytics::ReportMetrics.percentage_total_visitors(visits)
    sorted_names = sorted_names_for(grouped_visit_ids, counts, total)
    paged_names, has_more = Analytics::Pagination.paginate_names(sorted_names, limit: limit, page: page)
    page_visit_ids = grouped_visit_ids.slice(*paged_names)
    source_previews = mode == "all" ? Analytics::Sources.debug_previews(page_visit_ids) : {}

    if goal.present?
      goal_payload(page_visit_ids, paged_names, source_previews, has_more)
    else
      metrics_payload(page_visit_ids, paged_names, source_previews, counts, total, has_more)
    end
  end

  private
    attr_reader :query, :limit, :page, :search, :order_by

    def mode
      query.mode || "all"
    end

    def comparison_names
      query.comparison_filter_names
    end

    def range
      @range ||= begin
        raw_range, = Analytics::Ranges.range_and_interval_for(query.time_range_key, nil, query)
        raw_range
      end
    end

    def visits
      @visits ||= Analytics::VisitScope.visits(range, query)
    end

    def goal
      query.filter_value(:goal).presence
    end

    def paged?
      limit.present? && page.present?
    end

    def utm_mode?
      mode.start_with?("utm-")
    end

    def source_sql
      @source_sql ||= Analytics::Sources.mode_sql(mode)
    end

    def expr
      source_sql.first
    end

    def where_clause
      source_sql.last
    end

    def paged_grouped_visit_ids
      relation = visits
      if search.present? && where_clause.present?
        relation = relation.where([ where_clause, Analytics::Search.contains_pattern(search) ])
      end

      relation.group(Arel.sql(expr)).pluck(Arel.sql("#{expr}, ARRAY_AGG(ahoy_visits.id)")).to_h
    end

    def remove_empty_utm_groups!(grouped_visit_ids, counts)
      grouped_visit_ids.delete(nil)
      grouped_visit_ids.delete("")
      grouped_visit_ids.delete("(not set)")
      counts.delete(nil)
      counts.delete("")
      counts.delete("(not set)")
    end

    def sorted_names_for(grouped_visit_ids, counts, total)
      if goal.present?
        denominator_counts = Analytics::Sources.goal_denominator_counts(query, mode: mode, search: search)
        conversions, conversion_rates = Analytics::ReportMetrics.conversions_and_rates(
          grouped_visit_ids,
          visits,
          range,
          query,
          goal,
          denominator_counts: denominator_counts
        )
        Analytics::Ordering.order_names_with_conversions(conversions: conversions, cr: conversion_rates, order_by: order_by)
      elsif order_by
        order_metrics = Analytics::Sources.order_metrics(order_by, grouped_visit_ids, counts, range, query, total)
        Analytics::Ordering.order_names(counts: counts, metrics_map: order_metrics, order_by: order_by)
      else
        Analytics::Ordering.order_names(counts: counts, metrics_map: {}, order_by: nil)
      end
    end

    def goal_payload(page_visit_ids, paged_names, source_previews, has_more)
      denominator_counts = Analytics::Sources.goal_denominator_counts(query, mode: mode, search: search)
      conversions, = Analytics::ReportMetrics.conversions_and_rates(
        page_visit_ids,
        visits,
        range,
        query,
        goal,
        denominator_counts: denominator_counts
      )

      results = paged_names.map do |name|
        label = Analytics::Sources.formatted_name(mode, name)
        row = {
          name: label,
          visitors: conversions[name] || 0,
          conversion_rate: Analytics::ReportMetrics.goal_conversion_rate(conversions[name] || 0, denominator_counts[label])
        }
        row[:source_info] = source_previews[name] if source_previews[name]
        row
      end

      {
        results: results,
        metrics: %i[visitors conversion_rate],
        meta: {
          has_more: has_more,
          skip_imported_reason: Analytics::Imports.skip_reason(query),
          metric_labels: { visitors: "Conversions", conversionRate: "Conversion Rate" }
        }
      }
    end

    def metrics_payload(page_visit_ids, paged_names, source_previews, counts, total, has_more)
      metrics = Analytics::ReportMetrics.calculate_group_metrics(page_visit_ids, range, query)

      results = paged_names.map do |name|
        row = {
          name: Analytics::Sources.formatted_name(mode, name),
          visitors: counts[name],
          percentage: (counts[name].to_f / total).round(3),
          bounce_rate: metrics.dig(name, :bounce_rate),
          visit_duration: metrics.dig(name, :visit_duration)
        }
        row[:source_info] = source_previews[name] if source_previews[name]
        row
      end

      {
        results: results,
        metrics: %i[visitors percentage bounce_rate visit_duration],
        meta: {
          has_more: has_more,
          skip_imported_reason: Analytics::Imports.skip_reason(query),
          metric_labels: { percentage: "Percentage" }
        }
      }
    end

    def full_payload
      counts = visits.group(Arel.sql(expr)).count("DISTINCT visitor_token")
      remove_empty_utm_groups!(counts, counts) if utm_mode?
      total = Analytics::ReportMetrics.percentage_total_visitors(visits)
      rows = counts.sort_by { |_, value| -value }.map do |name, value|
        {
          name: Analytics::Sources.formatted_name(mode, name),
          visitors: value,
          percentage: (value.to_f / total).round(3)
        }
      end

      {
        results: rows,
        metrics: %i[visitors percentage],
        meta: {
          has_more: false,
          skip_imported_reason: Analytics::Imports.skip_reason(query),
          metric_labels: { percentage: "Percentage" }
        }
      }
    end
end
