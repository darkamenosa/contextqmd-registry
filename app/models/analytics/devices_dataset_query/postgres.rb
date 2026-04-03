# frozen_string_literal: true

class Analytics::DevicesDatasetQuery::Postgres
  def initialize(query:, limit:, page:, search:, order_by:)
    @query = Analytics::Query.wrap(query)
    @limit = limit
    @page = page
    @search = search
    @order_by = order_by
  end

  def payload
    screen_sizes_mode? ? screen_sizes_payload : devices_payload
  end

  private
    attr_reader :query, :limit, :page, :search, :order_by

    def mode
      query.mode || "browsers"
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

    def screen_sizes_mode?
      mode == "screen-sizes"
    end

    def screen_sizes_payload
      relation = screen_sizes_relation
      counts = relation.group(Arel.sql(screen_size_expression)).count("DISTINCT visitor_token")
      counts.select! { |name, _| comparison_names.include?(name.to_s) } if comparison_names.any?

      return unpaged_screen_sizes_payload(counts) unless paged?

      total = Analytics::ReportMetrics.percentage_total_visitors(visits)
      denominator_counts = goal.present? ? Analytics::Devices.goal_denominator_counts(query, mode: mode, search: search) : nil
      categorized_visit_ids = nil

      unless screen_sizes_count_first_path?
        categorized_visit_ids = grouped_screen_size_visit_ids(relation)
        categorized_visit_ids.select! { |name, _| counts.key?(name) }
      end

      sorted_names =
        if goal.present?
          conversions_all, conversion_rates = Analytics::ReportMetrics.conversions_and_rates(
            categorized_visit_ids,
            visits,
            range,
            query,
            goal,
            denominator_counts: denominator_counts
          )
          Analytics::Ordering.order_names_with_conversions(conversions: conversions_all, cr: conversion_rates, order_by: order_by)
        else
          metrics_map = {}
          if order_by
            metric, = order_by
            if metric == "percentage"
              metrics_map = counts.keys.index_with { |name| { percentage: (counts[name].to_f / total) } }
            elsif %w[bounce_rate visit_duration].include?(metric)
              metrics_all = Analytics::ReportMetrics.calculate_group_metrics(categorized_visit_ids, range, query)
              metrics_map = counts.keys.index_with { |name| metrics_all[name] || {} }
            end
          end

          Analytics::Ordering.order_names(counts: counts, metrics_map: metrics_map, order_by: order_by)
        end

      paged_names, has_more = Analytics::Pagination.paginate_names(sorted_names, limit: limit, page: page)
      grouped_page_visit_ids = categorized_visit_ids || grouped_screen_size_visit_ids(relation, names: paged_names)
      grouped_page_visit_ids = grouped_page_visit_ids.slice(*paged_names)

      if goal.present?
        conversions, = Analytics::ReportMetrics.conversions_and_rates(
          grouped_page_visit_ids,
          visits,
          range,
          query,
          goal,
          denominator_counts: denominator_counts
        )
        page_items = paged_names.map do |name|
          {
            name: name.to_s,
            visitors: conversions[name] || 0,
            conversion_rate: Analytics::ReportMetrics.goal_conversion_rate(conversions[name] || 0, denominator_counts[name.to_s])
          }
        end

        {
          results: page_items,
          metrics: %i[visitors conversion_rate],
          meta: {
            has_more: has_more,
            skip_imported_reason: Analytics::Imports.skip_reason(query),
            metric_labels: { visitors: "Conversions", conversionRate: "Conversion Rate" }
          }
        }
      else
        page_items = paged_names.map do |name|
          visitors_count = counts[name]
          { name: name, visitors: visitors_count, percentage: (visitors_count.to_f / total).round(3) }
        end
        group_metrics = Analytics::ReportMetrics.calculate_group_metrics(grouped_page_visit_ids, range, query)
        page_items.each do |item|
          item[:bounce_rate] = group_metrics.dig(item[:name], :bounce_rate)
          item[:visit_duration] = group_metrics.dig(item[:name], :visit_duration)
        end

        {
          results: page_items,
          metrics: %i[visitors percentage bounce_rate visit_duration],
          meta: { has_more: has_more, skip_imported_reason: Analytics::Imports.skip_reason(query) }
        }
      end
    end

    def unpaged_screen_sizes_payload(counts)
      total = Analytics::ReportMetrics.percentage_total_visitors(visits)
      results = counts.map do |name, visitors_count|
        {
          name: name.to_s.presence || Ahoy::Visit::Constants::UNKNOWN_LABEL,
          visitors: visitors_count,
          percentage: (visitors_count.to_f / total).round(3)
        }
      end
      {
        results: results,
        metrics: %i[visitors percentage],
        meta: { has_more: false, skip_imported_reason: Analytics::Imports.skip_reason(query) }
      }
    end

    def devices_payload
      grouping = Analytics::Devices.grouping_for_mode(mode)
      pattern = search.present? ? Analytics::Search.contains_pattern(search) : nil

      return unpaged_devices_payload(grouping) unless paged?

      relation = visits
      relation = Analytics::Devices.apply_search(relation, grouping, pattern) if pattern.present?
      disambiguate_by_meta = Analytics::Devices.disambiguate_versions?(grouping, query.filters)

      if devices_count_first_path?
        counts, group_metadata, group_keys = Analytics::Devices.normalize_group_counts(
          Analytics::Devices.pluck_group_count_rows(relation, grouping),
          meta_key: grouping[:meta_key],
          disambiguate_by_meta: disambiguate_by_meta
        )
        grouped_visit_ids = nil
      else
        grouped_visit_ids, group_metadata = Analytics::Devices.normalize_grouped_visit_ids(
          Analytics::Devices.pluck_group_rows(relation, grouping),
          meta_key: grouping[:meta_key],
          disambiguate_by_meta: disambiguate_by_meta
        )
        counts = Analytics::ReportMetrics.unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits)
        group_keys = nil
      end

      if comparison_names.any?
        grouped_visit_ids&.select! { |name, _| comparison_names.include?(Analytics::Devices.formatted_name(name)) }
        counts.select! { |name, _| comparison_names.include?(Analytics::Devices.formatted_name(name)) }
        group_metadata.select! { |name, _| comparison_names.include?(Analytics::Devices.formatted_name(name)) }
        group_keys&.select! { |name, _| comparison_names.include?(Analytics::Devices.formatted_name(name)) }
      end

      total = Analytics::ReportMetrics.percentage_total_visitors(visits)
      denominator_counts = goal.present? ? Analytics::Devices.goal_denominator_counts(query, mode: mode, search: search) : nil

      sorted_names =
        if goal.present?
          conversions_all, conversion_rates = Analytics::ReportMetrics.conversions_and_rates(
            grouped_visit_ids,
            visits,
            range,
            query,
            goal,
            denominator_counts: denominator_counts
          )
          Analytics::Ordering.order_names_with_conversions(conversions: conversions_all, cr: conversion_rates, order_by: order_by)
        else
          metrics_map = {}
          if order_by
            metric, = order_by
            if metric == "percentage"
              metrics_map = counts.keys.index_with { |name| { percentage: (counts[name].to_f / total) } }
            elsif %w[bounce_rate visit_duration].include?(metric)
              metrics_all = Analytics::ReportMetrics.calculate_group_metrics(grouped_visit_ids, range, query)
              metrics_map = counts.keys.index_with { |name| metrics_all[name] || {} }
            end
          end

          Analytics::Ordering.order_names(counts: counts, metrics_map: metrics_map, order_by: order_by)
        end

      paged_names, has_more = Analytics::Pagination.paginate_names(sorted_names, limit: limit, page: page)
      page_visit_ids =
        if grouped_visit_ids
          grouped_visit_ids.slice(*paged_names)
        else
          Analytics::Devices.grouped_visit_ids_for_names(
            relation,
            grouping,
            group_keys_by_name: group_keys,
            names: paged_names,
            meta_key: grouping[:meta_key],
            disambiguate_by_meta: disambiguate_by_meta
          )
        end

      if goal.present?
        conversions, = Analytics::ReportMetrics.conversions_and_rates(
          page_visit_ids,
          visits,
          range,
          query,
          goal,
          denominator_counts: denominator_counts
        )
        results = paged_names.map do |name|
          label = name.to_s.presence || Ahoy::Visit::Constants::UNKNOWN_LABEL
          Analytics::Devices.build_result(
            name: label,
            group_metadata: group_metadata,
            metrics: {
              visitors: conversions[name] || 0,
              conversion_rate: Analytics::ReportMetrics.goal_conversion_rate(conversions[name] || 0, denominator_counts[label])
            }
          )
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
        results = paged_names.map do |name|
          visitors_count = counts[name]
          Analytics::Devices.build_result(
            name: name.to_s.presence || Ahoy::Visit::Constants::UNKNOWN_LABEL,
            group_metadata: group_metadata,
            metrics: {
              visitors: visitors_count,
              percentage: (visitors_count.to_f / total).round(3)
            }
          )
        end
        group_metrics = Analytics::ReportMetrics.calculate_group_metrics(page_visit_ids, range, query)
        paged_names.each_with_index do |name, index|
          results[index][:bounce_rate] = group_metrics.dig(name, :bounce_rate)
          results[index][:visit_duration] = group_metrics.dig(name, :visit_duration)
        end

        {
          results: results,
          metrics: %i[visitors percentage bounce_rate visit_duration],
          meta: { has_more: has_more, skip_imported_reason: Analytics::Imports.skip_reason(query) }
        }
      end
    end

    def devices_count_first_path?
      return false if goal.present?

      metric = order_by&.first
      !metric.in?(%w[bounce_rate visit_duration])
    end

    def screen_sizes_count_first_path?
      return false if goal.present?

      metric = order_by&.first
      !metric.in?(%w[bounce_rate visit_duration])
    end

    def screen_sizes_relation
      relation = visits
      if search.present?
        relation = relation.where(
          Analytics::SqlExpression.lower_matches(
            screen_size_expression,
            Analytics::Search.contains_pattern(search)
          )
        )
      end
      relation
    end

    def grouped_screen_size_visit_ids(relation, names: nil)
      return {} if names == []

      scoped = relation
      scoped = scoped.where(Analytics::SqlExpression.in_list(screen_size_expression, names)) unless names.nil?
      scoped.group(Arel.sql(screen_size_expression)).pluck(Arel.sql("#{screen_size_expression}, ARRAY_AGG(ahoy_visits.id)")).to_h
    end

    def screen_size_expression
      @screen_size_expression ||= Analytics::Devices.screen_size_category_sql("screen_size")
    end

    def unpaged_devices_payload(grouping)
      grouped_visit_ids, group_metadata = Analytics::Devices.normalize_grouped_visit_ids(
        Analytics::Devices.pluck_group_rows(visits, grouping),
        meta_key: grouping[:meta_key],
        disambiguate_by_meta: Analytics::Devices.disambiguate_versions?(grouping, query.filters)
      )
      counts = Analytics::ReportMetrics.unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits)
      total = Analytics::ReportMetrics.percentage_total_visitors(visits)
      results = counts.map do |name, visitors_count|
        Analytics::Devices.build_result(
          name: name.to_s.presence || Ahoy::Visit::Constants::UNKNOWN_LABEL,
          group_metadata: group_metadata,
          metrics: {
            visitors: visitors_count,
            percentage: (visitors_count.to_f / total).round(3)
          }
        )
      end

      {
        results: results,
        metrics: %i[visitors percentage],
        meta: { has_more: false, skip_imported_reason: Analytics::Imports.skip_reason(query) }
      }
    end
end
