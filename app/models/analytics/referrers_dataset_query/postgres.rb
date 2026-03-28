# frozen_string_literal: true

class Analytics::ReferrersDatasetQuery::Postgres
  def initialize(query:, source:, limit:, page:, search:, order_by:)
    @query = Analytics::Query.wrap(query)
    @source = source
    @limit = limit
    @page = page
    @search = search
    @order_by = order_by
  end

  def payload
    direct_source? ? direct_payload : grouped_payload
  end

  private
    attr_reader :query, :source, :limit, :page, :search, :order_by

    def comparison_names
      query.comparison_filter_names
    end

    def goal
      query.filter_value(:goal).presence
    end

    def range
      @range ||= begin
        raw_range, = Analytics::Ranges.range_and_interval_for(query.time_range_key, nil, query)
        raw_range
      end
    end

    def normalized_source
      @normalized_source ||= Analytics::Sources.normalize_name(source)
    end

    def base_visits
      @base_visits ||= Analytics::VisitScope.visits(range, query)
    end

    def visits
      @visits ||= Analytics::Sources.filter_scope(base_visits, source)
    end

    def paged?
      limit.present? && page.present?
    end

    def direct_source?
      normalized_source == Analytics::SourceResolver::DIRECT_LABEL
    end

    def direct_payload
      counts = { Analytics::SourceResolver::DIRECT_LABEL => visits.distinct.count(:visitor_token) }
      counts = {} if comparison_names.any? && !comparison_names.include?(Analytics::SourceResolver::DIRECT_LABEL)

      return direct_full_payload(counts) unless paged?

      grouped_visit_ids = counts.empty? ? {} : { Analytics::SourceResolver::DIRECT_LABEL => visits.pluck(:id) }

      if goal.present?
        denominator_counts = Analytics::Sources.referrer_goal_denominator_counts(query, normalized_source, search: search)
        conversions, = Analytics::ReportMetrics.conversions_and_rates(
          grouped_visit_ids,
          visits,
          range,
          query,
          goal,
          denominator_counts: denominator_counts
        )

        rows = counts.map do |name, _|
          {
            name: name,
            visitors: conversions[name] || 0,
            conversion_rate: Analytics::ReportMetrics.goal_conversion_rate(conversions[name] || 0, denominator_counts[name])
          }
        end

        {
          results: rows,
          metrics: %i[visitors conversion_rate],
          meta: {
            has_more: false,
            skip_imported_reason: Analytics::Imports.skip_reason(query),
            metric_labels: { visitors: "Conversions", conversionRate: "Conversion Rate" }
          }
        }
      else
        metrics = Analytics::ReportMetrics.calculate_group_metrics(grouped_visit_ids, range, query)
        rows = counts.map do |name, value|
          {
            name: name,
            visitors: value,
            bounce_rate: metrics.dig(name, :bounce_rate),
            visit_duration: metrics.dig(name, :visit_duration)
          }
        end

        {
          results: rows,
          metrics: %i[visitors bounce_rate visit_duration],
          meta: { has_more: false, skip_imported_reason: Analytics::Imports.skip_reason(query) }
        }
      end
    end

    def direct_full_payload(counts)
      rows = counts.sort_by { |_, value| -value }.map { |name, value| { name: name, visitors: value } }
      {
        results: rows,
        metrics: %i[visitors],
        meta: { has_more: false, skip_imported_reason: Analytics::Imports.skip_reason(query) }
      }
    end

    def grouped_payload
      expression = "COALESCE(referrer, '#{Analytics::SourceResolver::DIRECT_LABEL}')"
      relation = visits
      relation = relation.where("LOWER(referrer) LIKE ?", Analytics::Search.contains_pattern(search)) if search.present?

      return grouped_full_payload(relation, expression) unless paged?

      grouped_visit_ids = relation.group(Arel.sql(expression)).pluck(Arel.sql("#{expression}, ARRAY_AGG(ahoy_visits.id)")).to_h
      counts = Analytics::ReportMetrics.unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits)

      if comparison_names.any?
        grouped_visit_ids.select! { |name, _| comparison_names.include?(name.to_s) }
        counts.select! { |name, _| comparison_names.include?(name.to_s) }
      end

      sorted_names =
        if goal.present?
          denominator_counts = Analytics::Sources.referrer_goal_denominator_counts(query, normalized_source, search: search)
          conversions, conversion_rates = Analytics::ReportMetrics.conversions_and_rates(
            grouped_visit_ids,
            visits,
            range,
            query,
            goal,
            denominator_counts: denominator_counts
          )
          Analytics::Ordering.order_names_with_conversions(conversions: conversions, cr: conversion_rates, order_by: order_by)
        elsif order_by && %w[bounce_rate visit_duration].include?(order_by[0])
          metrics = Analytics::ReportMetrics.calculate_group_metrics(grouped_visit_ids, range, query)
          Analytics::Ordering.order_names(counts: counts, metrics_map: counts.keys.index_with { |name| metrics[name] || {} }, order_by: order_by)
        else
          Analytics::Ordering.order_names(counts: counts, metrics_map: {}, order_by: order_by)
        end

      paged_names, has_more = Analytics::Pagination.paginate_names(sorted_names, limit: limit, page: page)
      page_visit_ids = grouped_visit_ids.slice(*paged_names)

      if goal.present?
        denominator_counts = Analytics::Sources.referrer_goal_denominator_counts(query, normalized_source, search: search)
        conversions, = Analytics::ReportMetrics.conversions_and_rates(
          page_visit_ids,
          visits,
          range,
          query,
          goal,
          denominator_counts: denominator_counts
        )
        results = paged_names.map do |name|
          {
            name: name,
            visitors: conversions[name] || 0,
            conversion_rate: Analytics::ReportMetrics.goal_conversion_rate(conversions[name] || 0, denominator_counts[name])
          }
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
      else
        metrics = Analytics::ReportMetrics.calculate_group_metrics(page_visit_ids, range, query)
        results = paged_names.map do |name|
          {
            name: name,
            visitors: counts[name],
            bounce_rate: metrics.dig(name, :bounce_rate),
            visit_duration: metrics.dig(name, :visit_duration)
          }
        end

        {
          results: results,
          metrics: %i[visitors bounce_rate visit_duration],
          meta: { has_more: has_more, skip_imported_reason: Analytics::Imports.skip_reason(query) }
        }
      end
    end

    def grouped_full_payload(relation, expression)
      counts = relation.group(Arel.sql(expression)).distinct.count(:visitor_token)
      rows = counts.sort_by { |_, value| -value }.map do |name, value|
        { name: name.to_s.presence || "(none)", visitors: value }
      end

      {
        results: rows,
        metrics: %i[visitors],
        meta: { has_more: false, skip_imported_reason: Analytics::Imports.skip_reason(query) }
      }
    end
end
