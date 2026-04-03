# frozen_string_literal: true

class Analytics::LocationsDatasetQuery::Postgres
  def initialize(query:, limit:, page:, search:, order_by:)
    @query = Analytics::Query.wrap(query)
    @limit = limit
    @page = page
    @search = search
    @order_by = order_by
  end

  def payload
    case mode
    when "map" then map_payload
    when "countries" then countries_payload
    when "regions" then regions_payload
    when "cities" then cities_payload
    else
      default_payload
    end
  end

  private
    attr_reader :query, :limit, :page, :search, :order_by

    def mode
      query.mode || "map"
    end

    def comparison_names
      query.comparison_filter_names
    end

    def comparison_codes
      query.comparison_filter_codes
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

    def map_payload
      return map_rollup_payload if location_rollup_eligible?

      counts = visits.group(Arel.sql(Analytics::Locations.country_code_expression)).count("DISTINCT visitor_token")
      Analytics::Locations.map_from_counts(counts)
    end

    def countries_payload
      return countries_rollup_payload if location_rollup_eligible?
      return all_countries_payload unless paged?

      relation = countries_relation
      grouped_visit_ids = nil

      if goal.present?
        grouped_visit_ids = grouped_location_visit_ids(relation, countries_expression)
        counts = Analytics::ReportMetrics.unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits)
        Analytics::Locations.filter_groups!("countries", grouped_visit_ids, counts, comparison_names, comparison_codes)
      else
        counts = relation.group(Arel.sql(countries_expression)).count("DISTINCT visitor_token")
        Analytics::Locations.filter_groups!("countries", {}, counts, comparison_names, comparison_codes)
      end

      total = Analytics::ReportMetrics.percentage_total_visitors(visits)

      if goal.present?
        denominator_counts = Analytics::Locations.goal_denominator_counts(query, mode: mode, search: search)
        conversions, conversion_rates = Analytics::ReportMetrics.conversions_and_rates(
          grouped_visit_ids,
          visits,
          range,
          query,
          goal,
          denominator_counts: denominator_counts
        )
        sorted_names = Analytics::Ordering.order_names_with_conversions(conversions: conversions, cr: conversion_rates, order_by: order_by)
        paged_names, has_more = Analytics::Pagination.paginate_names(sorted_names, limit: limit, page: page)

        items = paged_names.map do |code|
          code_string = code.to_s
          name = code_string.present? && code_string != "(unknown)" ? Analytics::Locations.country_name_for(code_string) : "(unknown)"
          {
            name: name,
            code: code_string != "(unknown)" ? code_string : nil,
            visitors: conversions[code] || 0,
            conversion_rate: Analytics::ReportMetrics.goal_conversion_rate(conversions[code] || 0, denominator_counts[name])
          }.compact
        end

        {
          results: items,
          metrics: %i[visitors conversion_rate],
          meta: {
            has_more: has_more,
            skip_imported_reason: Analytics::Imports.skip_reason(query),
            metric_labels: { visitors: "Conversions", conversionRate: "Conversion Rate" }
          }
        }
      else
        sorted_names =
          if order_by&.first == "percentage"
            percentages = counts.keys.index_with { |key| { percentage: (counts[key].to_f / total) } }
            Analytics::Ordering.order_names(counts: counts, metrics_map: percentages, order_by: order_by)
          else
            Analytics::Ordering.order_names(counts: counts, metrics_map: {}, order_by: order_by)
          end

        paged_names, has_more = Analytics::Pagination.paginate_names(sorted_names, limit: limit, page: page)
        items = paged_names.map do |code|
          visitors = counts[code]
          code_string = code.to_s
          name = code_string.present? && code_string != "(unknown)" ? Analytics::Locations.country_name_for(code_string) : "(unknown)"
          {
            name: name,
            code: code_string != "(unknown)" ? code_string : nil,
            visitors: visitors,
            percentage: (visitors.to_f / total).round(3)
          }.compact
        end

        {
          results: items,
          metrics: %i[visitors percentage],
          meta: {
            has_more: has_more,
            skip_imported_reason: Analytics::Imports.skip_reason(query),
            metric_labels: { percentage: "Percentage" }
          }
        }
      end
    end

    def all_countries_payload
      counts = visits.group(Arel.sql(Analytics::Locations.country_code_expression)).count("DISTINCT visitor_token")
      total = Analytics::ReportMetrics.percentage_total_visitors(visits)

      items = counts.map do |code, visitors|
        code_string = code.to_s
        if code_string.present?
          normalized_code = Ahoy::Visit.normalize_country_code(code_string)
          if normalized_code.present?
            { name: Analytics::Locations.country_name_for(normalized_code), code: normalized_code, visitors: visitors, percentage: (visitors.to_f / total).round(3) }
          else
            { name: code_string, visitors: visitors, percentage: (visitors.to_f / total).round(3) }
          end
        else
          { name: "(unknown)", visitors: visitors, percentage: (visitors.to_f / total).round(3) }
        end
      end

      {
        results: items.sort_by { |item| [ -item[:visitors].to_i, item[:name].to_s ] },
        metrics: %i[visitors percentage],
        meta: {
            has_more: false,
            skip_imported_reason: Analytics::Imports.skip_reason(query),
          metric_labels: { percentage: "Percentage" }
        }
      }
    end

    def regions_payload
      return regions_rollup_payload if location_rollup_eligible?
      return all_regions_payload unless paged?

      relation = grouped_locations_relation(regions_expression)
      grouped_visit_ids = nil

      if goal.present?
        grouped_visit_ids = grouped_location_visit_ids(relation, regions_expression)
        counts = Analytics::ReportMetrics.unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits)
        Analytics::Locations.filter_groups!("regions", grouped_visit_ids, counts, comparison_names, comparison_codes)
      else
        counts = relation.group(Arel.sql(regions_expression)).count("DISTINCT visitor_token")
        Analytics::Locations.filter_groups!("regions", {}, counts, comparison_names, comparison_codes)
      end

      total = Analytics::ReportMetrics.percentage_total_visitors(visits)

      if goal.present?
        denominator_counts = Analytics::Locations.goal_denominator_counts(query, mode: mode, search: search)
        conversions, conversion_rates = Analytics::ReportMetrics.conversions_and_rates(
          grouped_visit_ids,
          visits,
          range,
          query,
          goal,
          denominator_counts: denominator_counts
        )
        sorted_names = Analytics::Ordering.order_names_with_conversions(conversions: conversions, cr: conversion_rates, order_by: order_by)
        paged_names, has_more = Analytics::Pagination.paginate_names(sorted_names, limit: limit, page: page)
        flags_by_region = Analytics::Locations.country_flags_for_grouped(grouped_visit_ids.slice(*paged_names), visits, :region, query)

        results = paged_names.map do |name|
          label = name.to_s.presence || "(none)"
          {
            name: label,
            visitors: conversions[name] || 0,
            conversion_rate: Analytics::ReportMetrics.goal_conversion_rate(conversions[name] || 0, denominator_counts[label]),
            country_flag: flags_by_region[name]
          }.compact
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
        metrics_map =
          if order_by&.first == "percentage"
            counts.keys.index_with { |name| { percentage: (counts[name].to_f / total) } }
          else
            {}
          end
        sorted_names = Analytics::Ordering.order_names(counts: counts, metrics_map: metrics_map, order_by: order_by)
        paged_names, has_more = Analytics::Pagination.paginate_names(sorted_names, limit: limit, page: page)
        paged_visit_ids = grouped_visit_ids || grouped_location_visit_ids(relation, regions_expression, names: paged_names)
        flags_by_region = Analytics::Locations.country_flags_for_grouped(paged_visit_ids, visits, :region, query)

        results = paged_names.map do |name|
          visitors = counts[name]
          {
            name: name.to_s.presence || "(none)",
            visitors: visitors,
            percentage: (visitors.to_f / total).round(3),
            country_flag: flags_by_region[name]
          }.compact
        end

        {
          results: results,
          metrics: %i[visitors percentage],
          meta: {
            has_more: has_more,
            skip_imported_reason: Analytics::Imports.skip_reason(query),
            metric_labels: { percentage: "Percentage" }
          }
        }
      end
    end

    def all_regions_payload
      counts = visits.group(:region).count("DISTINCT visitor_token")
      total = Analytics::ReportMetrics.percentage_total_visitors(visits)
      flags_by_region =
        if query.filter_value(:country).present?
          code = Ahoy::Visit.normalize_country_code(query.filter_value(:country))
          flag = Analytics::Locations.emoji_flag_for(code)
          counts.keys.each_with_object({}) { |region, flags| flags[region] = flag }
        else
          pairs = visits.group(:region, Arel.sql(Analytics::Locations.country_code_expression)).count("DISTINCT visitor_token")
          dominant = Hash.new { |hash, key| hash[key] = { country: nil, count: -1 } }
          pairs.each do |(region, country), count|
            next if region.blank?

            current = dominant[region]
            dominant[region] = { country: country, count: count.to_i } if count.to_i > current[:count].to_i
          end
          dominant.transform_values { |value| Analytics::Locations.emoji_flag_for(value[:country].to_s.upcase) }
        end

      rows = counts.sort_by { |_, visitors| -visitors.to_i }.map do |name, visitors|
        label = name.to_s.presence || "(unknown)"
        row = { name: label, visitors: visitors, percentage: (visitors.to_f / total).round(3) }
        flag = flags_by_region[name]
        flag.present? ? row.merge(country_flag: flag) : row
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

    def cities_payload
      return cities_rollup_payload if location_rollup_eligible?
      return all_cities_payload unless paged?

      relation = grouped_locations_relation(cities_expression)
      grouped_visit_ids = nil

      if goal.present?
        grouped_visit_ids = grouped_location_visit_ids(relation, cities_expression)
        counts = Analytics::ReportMetrics.unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits)
        Analytics::Locations.filter_groups!("cities", grouped_visit_ids, counts, comparison_names, comparison_codes)
      else
        counts = relation.group(Arel.sql(cities_expression)).count("DISTINCT visitor_token")
        Analytics::Locations.filter_groups!("cities", {}, counts, comparison_names, comparison_codes)
      end

      total = Analytics::ReportMetrics.percentage_total_visitors(visits)

      if goal.present?
        denominator_counts = Analytics::Locations.goal_denominator_counts(query, mode: mode, search: search)
        conversions, conversion_rates = Analytics::ReportMetrics.conversions_and_rates(
          grouped_visit_ids,
          visits,
          range,
          query,
          goal,
          denominator_counts: denominator_counts
        )
        sorted_names = Analytics::Ordering.order_names_with_conversions(conversions: conversions, cr: conversion_rates, order_by: order_by)
        paged_names, has_more = Analytics::Pagination.paginate_names(sorted_names, limit: limit, page: page)
        flags_by_city = Analytics::Locations.country_flags_for_grouped(grouped_visit_ids.slice(*paged_names), visits, :city, query)

        results = paged_names.map do |name|
          label = name.to_s.presence || "(none)"
          {
            name: label,
            visitors: conversions[name] || 0,
            conversion_rate: Analytics::ReportMetrics.goal_conversion_rate(conversions[name] || 0, denominator_counts[label]),
            country_flag: flags_by_city[name]
          }.compact
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
        metrics_map =
          if order_by&.first == "percentage"
            counts.keys.index_with { |name| { percentage: (counts[name].to_f / total) } }
          else
            {}
          end
        sorted_names = Analytics::Ordering.order_names(counts: counts, metrics_map: metrics_map, order_by: order_by)
        paged_names, has_more = Analytics::Pagination.paginate_names(sorted_names, limit: limit, page: page)
        paged_visit_ids = grouped_visit_ids || grouped_location_visit_ids(relation, cities_expression, names: paged_names)
        flags_by_city = Analytics::Locations.country_flags_for_grouped(paged_visit_ids, visits, :city, query)

        results = paged_names.map do |name|
          visitors = counts[name]
          {
            name: name.to_s.presence || "(none)",
            visitors: visitors,
            percentage: (visitors.to_f / total).round(3),
            country_flag: flags_by_city[name]
          }.compact
        end

        {
          results: results,
          metrics: %i[visitors percentage],
          meta: {
            has_more: has_more,
            skip_imported_reason: Analytics::Imports.skip_reason(query),
            metric_labels: { percentage: "Percentage" }
          }
        }
      end
    end

    def all_cities_payload
      counts = visits.group(:city).count("DISTINCT visitor_token")
      total = Analytics::ReportMetrics.percentage_total_visitors(visits)
      flags_by_city =
        if query.filter_value(:country).present?
          code = Ahoy::Visit.normalize_country_code(query.filter_value(:country))
          flag = Analytics::Locations.emoji_flag_for(code)
          counts.keys.each_with_object({}) { |city, flags| flags[city] = flag }
        else
          pairs = visits.group(:city, Arel.sql(Analytics::Locations.country_code_expression)).count("DISTINCT visitor_token")
          dominant = Hash.new { |hash, key| hash[key] = { country: nil, count: -1 } }
          pairs.each do |(city, country), count|
            next if city.blank?

            current = dominant[city]
            dominant[city] = { country: country, count: count.to_i } if count.to_i > current[:count].to_i
          end
          dominant.transform_values { |value| Analytics::Locations.emoji_flag_for(value[:country].to_s.upcase) }
        end

      rows = counts.sort_by { |_, visitors| -visitors.to_i }.map do |name, visitors|
        label = name.to_s.presence || "(unknown)"
        row = { name: label, visitors: visitors, percentage: (visitors.to_f / total).round(3) }
        flag = flags_by_city[name]
        flag.present? ? row.merge(country_flag: flag) : row
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

    def default_payload
      counts = visits.group(Arel.sql(Analytics::Locations.country_code_expression)).count
      rows = counts.sort_by { |_, visitors| -visitors }.map do |name, visitors|
        { name: name.to_s.presence || "(none)", visitors: visitors }
      end

      {
        results: rows,
        metrics: %i[visitors],
        meta: {
          has_more: false,
          skip_imported_reason: Analytics::Imports.skip_reason(query)
        }
      }
    end

    def countries_relation
      relation = visits
      if search.present?
        matching_codes = Ahoy::Visit.matching_country_codes(search)
        relation = matching_codes.any? ? relation.where(country_code: matching_codes) : relation.none
      end
      relation
    end

    def grouped_locations_relation(expression)
      relation = visits
      if search.present?
        relation = relation.where(
          Analytics::SqlExpression.lower_matches(
            expression,
            Analytics::Search.contains_pattern(search)
          )
        )
      end
      relation
    end

    def grouped_location_visit_ids(relation, expression, names: nil)
      return {} if names == []

      scoped = relation
      scoped = scoped.where(Analytics::SqlExpression.in_list(expression, names)) unless names.nil?
      scoped.group(Arel.sql(expression)).pluck(Arel.sql("#{expression}, ARRAY_AGG(ahoy_visits.id)")).to_h
    end

    def countries_expression
      "COALESCE(#{Analytics::Locations.country_code_expression}, '(unknown)')"
    end

    def regions_expression
      "COALESCE(region, '(unknown)')"
    end

    def cities_expression
      "COALESCE(city, '(unknown)')"
    end

    def current_site
      Analytics::Current.site_or_default
    end

    def map_rollup_payload
      counts = Analytics::SiteLocationHourlyVisitorRollup.counts_for(
        range: range,
        site: current_site,
        dimension: "map"
      )
      Analytics::Locations.map_from_counts(counts)
    end

    def countries_rollup_payload
      counts = Analytics::SiteLocationHourlyVisitorRollup.counts_for(
        range: range,
        site: current_site,
        dimension: "countries",
        search: search
      )
      Analytics::Locations.filter_groups!("countries", {}, counts, comparison_names, comparison_codes)
      total = Analytics::ReportMetrics.percentage_total_visitors(visits)

      if paged?
        sorted_names =
          if order_by&.first == "percentage"
            percentages = counts.keys.index_with { |key| { percentage: counts[key].to_f / total } }
            Analytics::Ordering.order_names(counts: counts, metrics_map: percentages, order_by: order_by)
          else
            Analytics::Ordering.order_names(counts: counts, metrics_map: {}, order_by: order_by)
          end
        paged_names, has_more = Analytics::Pagination.paginate_names(sorted_names, limit: limit, page: page)
        results = paged_names.map { |code| country_result_row(code, counts[code], total) }
      else
        has_more = false
        results = counts
          .sort_by { |code, visitors| [ -visitors.to_i, country_label_sort_key(code) ] }
          .map { |code, visitors| country_result_row(code, visitors, total) }
      end

      {
        results: results,
        metrics: %i[visitors percentage],
        meta: {
          has_more: has_more,
          skip_imported_reason: Analytics::Imports.skip_reason(query),
          metric_labels: { percentage: "Percentage" }
        }
      }
    end

    def regions_rollup_payload
      counts = Analytics::SiteLocationHourlyVisitorRollup.counts_for(
        range: range,
        site: current_site,
        dimension: "regions",
        search: search
      )
      Analytics::Locations.filter_groups!("regions", {}, counts, comparison_names, comparison_codes)
      total = Analytics::ReportMetrics.percentage_total_visitors(visits)

      if paged?
        metrics_map =
          if order_by&.first == "percentage"
            counts.keys.index_with { |name| { percentage: counts[name].to_f / total } }
          else
            {}
          end
        sorted_names = Analytics::Ordering.order_names(counts: counts, metrics_map: metrics_map, order_by: order_by)
        paged_names, has_more = Analytics::Pagination.paginate_names(sorted_names, limit: limit, page: page)
        flags_by_region = flags_for_rollup("regions", paged_names)
        results = paged_names.map { |name| location_result_row(name, counts[name], total, flags_by_region[name]) }
      else
        has_more = false
        flags_by_region = flags_for_rollup("regions", counts.keys)
        results = counts
          .sort_by { |name, visitors| [ -visitors.to_i, name.to_s ] }
          .map { |name, visitors| location_result_row(name, visitors, total, flags_by_region[name]) }
      end

      {
        results: results,
        metrics: %i[visitors percentage],
        meta: {
          has_more: has_more,
          skip_imported_reason: Analytics::Imports.skip_reason(query),
          metric_labels: { percentage: "Percentage" }
        }
      }
    end

    def cities_rollup_payload
      counts = Analytics::SiteLocationHourlyVisitorRollup.counts_for(
        range: range,
        site: current_site,
        dimension: "cities",
        search: search
      )
      Analytics::Locations.filter_groups!("cities", {}, counts, comparison_names, comparison_codes)
      total = Analytics::ReportMetrics.percentage_total_visitors(visits)

      if paged?
        metrics_map =
          if order_by&.first == "percentage"
            counts.keys.index_with { |name| { percentage: counts[name].to_f / total } }
          else
            {}
          end
        sorted_names = Analytics::Ordering.order_names(counts: counts, metrics_map: metrics_map, order_by: order_by)
        paged_names, has_more = Analytics::Pagination.paginate_names(sorted_names, limit: limit, page: page)
        flags_by_city = flags_for_rollup("cities", paged_names)
        results = paged_names.map { |name| location_result_row(name, counts[name], total, flags_by_city[name]) }
      else
        has_more = false
        flags_by_city = flags_for_rollup("cities", counts.keys)
        results = counts
          .sort_by { |name, visitors| [ -visitors.to_i, name.to_s ] }
          .map { |name, visitors| location_result_row(name, visitors, total, flags_by_city[name]) }
      end

      {
        results: results,
        metrics: %i[visitors percentage],
        meta: {
          has_more: has_more,
          skip_imported_reason: Analytics::Imports.skip_reason(query),
          metric_labels: { percentage: "Percentage" }
        }
      }
    end

    def flags_for_rollup(dimension, names)
      return {} if names.blank?

      Analytics::SiteLocationHourlyVisitorRollup
        .dominant_country_codes_for(range: range, site: current_site, dimension: dimension, values: names)
        .transform_values { |country_code| Analytics::Locations.emoji_flag_for(country_code) }
    end

    def country_result_row(code, visitors, total)
      code_string = code.to_s
      name = code_string.present? && code_string != "(unknown)" ? Analytics::Locations.country_name_for(code_string) : "(unknown)"
      {
        name: name,
        code: code_string != "(unknown)" ? code_string : nil,
        visitors: visitors,
        percentage: (visitors.to_f / total).round(3)
      }.compact
    end

    def country_label_sort_key(code)
      code_string = code.to_s
      if code_string.present? && code_string != "(unknown)"
        Analytics::Locations.country_name_for(code_string).to_s
      else
        "(unknown)"
      end
    end

    def location_result_row(name, visitors, total, country_flag)
      row = {
        name: name.to_s.presence || "(unknown)",
        visitors: visitors,
        percentage: (visitors.to_f / total).round(3)
      }
      country_flag.present? ? row.merge(country_flag: country_flag) : row
    end

    def location_rollup_eligible?
      return false if goal.present?
      return false unless query.filter_dimensions.empty?
      return false unless query.advanced_filters.empty?
      return false unless Analytics::SiteLocationHourlyVisitorRollup.available?

      Analytics::SiteLocationHourlyVisitorRollup.usable_for?(range: range, site: current_site, dimension: mode)
    end
end
