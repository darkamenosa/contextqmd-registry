# frozen_string_literal: true

class Analytics::PagesDatasetQuery::Postgres
  SEO_METRICS = %i[clicks impressions ctr position visitors pageviews].freeze
  SEO_GOAL_METRICS = %i[clicks impressions ctr position visitors conversion_rate].freeze

  def initialize(query:, limit:, page:, search:, order_by:)
    @query = Analytics::Query.wrap(query)
    @limit = limit
    @page = page
    @search = search
    @order_by = order_by
  end

  def payload
    if paged?
      paginated_payload
    else
      full_payload
    end
  end

  private
    attr_reader :query, :limit, :page, :search, :order_by

    def mode
      query.mode || "pages"
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

    def events
      @events ||= Analytics::VisitScope.pageviews(range, query)
    end

    def goal
      query.filter_value(:goal).presence
    end

    def pattern
      @pattern ||= search.present? ? Analytics::Search.contains_pattern(search) : nil
    end

    def paged?
      limit.present? && page.present?
    end

    def paginated_payload
      case mode
      when "seo" then seo_payload(paginated: true)
      when "pages" then paginated_pages_payload
      when "entry" then paginated_entry_payload
      else
        paginated_exit_payload
      end
    end

    def full_payload
      case mode
      when "seo" then seo_payload(paginated: false)
      when "pages" then full_pages_payload
      when "entry" then full_entry_payload
      else
        full_exit_payload
      end
    end

    def paginated_pages_payload
      return paginated_pages_rollup_payload if page_rollup_eligible?

      relation = filtered_pages_relation
      pageviews_by_page = relation.group(Arel.sql(page_expression)).count
      grouped_visit_ids = nil

      if pages_count_first_path?
        counts = relation.group(Arel.sql(page_expression)).distinct.count("ahoy_visits.visitor_token")
        Analytics::Pages.filter_groups!({}, counts, comparison_names, pageviews_by_page)
      else
        grouped_visit_ids = grouped_page_visit_ids(relation)
        counts = Analytics::ReportMetrics.unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits)
        Analytics::Pages.filter_groups!(grouped_visit_ids, counts, comparison_names, pageviews_by_page)
      end

      total = Analytics::ReportMetrics.percentage_total_visitors(visits)

      sorted_names =
        if order_by
          metric, = order_by
          case metric
          when "percentage"
            Analytics::Ordering.order_names(
              counts: counts,
              metrics_map: counts.keys.index_with { |name| { percentage: (counts[name].to_f / total) } },
              order_by: order_by
            )
          when "pageviews"
            Analytics::Ordering.order_names(counts: pageviews_by_page, metrics_map: {}, order_by: order_by)
          when "bounce_rate", "visit_duration"
            metrics_all = Analytics::ReportMetrics.calculate_group_metrics(grouped_visit_ids, range, query)
            Analytics::Ordering.order_names(counts: counts, metrics_map: counts.keys.index_with { |name| metrics_all[name] || {} }, order_by: order_by)
          when "time_on_page", "scroll_depth"
            top_metrics_all = Analytics::Pages.time_on_page_and_scroll(range, query, grouped_visit_ids)
            Analytics::Ordering.order_names(counts: counts, metrics_map: counts.keys.index_with { |name| top_metrics_all[name] || {} }, order_by: order_by)
          else
            Analytics::Ordering.order_names(counts: counts, metrics_map: {}, order_by: order_by)
          end
        else
          Analytics::Ordering.order_names(counts: counts, metrics_map: {}, order_by: nil)
        end

      if goal.present?
        denominator_counts = Analytics::Pages.goal_denominator_counts(query, mode: mode, search: search)
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

        results = paged_names.map do |name|
          label = name.to_s.presence || "(none)"
          {
            name: label,
            visitors: conversions[name] || 0,
            conversion_rate: Analytics::ReportMetrics.goal_conversion_rate(conversions[name] || 0, denominator_counts[label])
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
        paged_names, has_more = Analytics::Pagination.paginate_names(sorted_names, limit: limit, page: page)
        page_visit_ids = grouped_visit_ids || grouped_page_visit_ids(relation, names: paged_names)
        entry_map = Analytics::Pages.entry_page_label_by_visit(visits, page_visit_ids)
        restricted = Analytics::Pages.restrict_visits_to_entry_page(page_visit_ids, entry_map)
        group_metrics = Analytics::ReportMetrics.calculate_group_metrics(restricted, range, query)
        tops = Analytics::Pages.time_on_page_and_scroll(range, query, page_visit_ids)

        results = paged_names.map do |name|
          visitors = counts[name]
          {
            name: name.to_s.presence || "(none)",
            visitors: visitors,
            percentage: (visitors.to_f / total).round(3),
            pageviews: pageviews_by_page[name] || 0,
            bounce_rate: group_metrics.dig(name, :bounce_rate),
            visit_duration: group_metrics.dig(name, :visit_duration),
            time_on_page: tops.dig(name, :time_on_page),
            scroll_depth: tops.dig(name, :scroll_depth)
          }
        end

        if query.with_imported?
          imported = Analytics::Imports.pages_aggregates(range)
          results.each do |row|
            next unless (counts_row = imported[row[:name]])

            row[:visitors] = row[:visitors].to_i + counts_row[:visitors].to_i
            row[:pageviews] = row[:pageviews].to_i + counts_row[:pageviews].to_i
          end
        end

        {
          results: results,
          metrics: %i[visitors percentage pageviews bounce_rate time_on_page scroll_depth],
          meta: {
            has_more: has_more,
            skip_imported_reason: Analytics::Imports.skip_reason(query),
            metric_labels: { percentage: "Percentage" }
          }
        }
      end
    end

    def paginated_pages_rollup_payload
      counts = Analytics::SitePageHourlyRollup.counts_for(range: range, site: current_site, search: search)
      pageviews_by_page = Analytics::SitePageHourlyRollup.pageviews_for(range: range, site: current_site, search: search)
      Analytics::Pages.filter_groups!({}, counts, comparison_names, pageviews_by_page)

      total = Analytics::ReportMetrics.percentage_total_visitors(visits)
      sorted_names =
        if order_by
          metric, = order_by
          case metric
          when "percentage"
            Analytics::Ordering.order_names(
              counts: counts,
              metrics_map: counts.keys.index_with { |name| { percentage: counts[name].to_f / total } },
              order_by: order_by
            )
          when "pageviews"
            Analytics::Ordering.order_names(counts: pageviews_by_page, metrics_map: {}, order_by: order_by)
          else
            Analytics::Ordering.order_names(counts: counts, metrics_map: {}, order_by: order_by)
          end
        else
          Analytics::Ordering.order_names(counts: counts, metrics_map: {}, order_by: nil)
        end

      paged_names, has_more = Analytics::Pagination.paginate_names(sorted_names, limit: limit, page: page)
      page_visit_ids = grouped_page_visit_ids(filtered_pages_relation, names: paged_names)
      entry_map = Analytics::Pages.entry_page_label_by_visit(visits, page_visit_ids)
      restricted = Analytics::Pages.restrict_visits_to_entry_page(page_visit_ids, entry_map)
      group_metrics = Analytics::ReportMetrics.calculate_group_metrics(restricted, range, query)
      tops = Analytics::Pages.time_on_page_and_scroll(range, query, page_visit_ids)

      results = paged_names.map do |name|
        visitors = counts[name]
        {
          name: name.to_s.presence || "(none)",
          visitors: visitors,
          percentage: (visitors.to_f / total).round(3),
          pageviews: pageviews_by_page[name] || 0,
          bounce_rate: group_metrics.dig(name, :bounce_rate),
          visit_duration: group_metrics.dig(name, :visit_duration),
          time_on_page: tops.dig(name, :time_on_page),
          scroll_depth: tops.dig(name, :scroll_depth)
        }
      end

      if query.with_imported?
        imported = Analytics::Imports.pages_aggregates(range)
        results.each do |row|
          next unless (counts_row = imported[row[:name]])

          row[:visitors] = row[:visitors].to_i + counts_row[:visitors].to_i
          row[:pageviews] = row[:pageviews].to_i + counts_row[:pageviews].to_i
        end
      end

      {
        results: results,
        metrics: %i[visitors percentage pageviews bounce_rate time_on_page scroll_depth],
        meta: {
          has_more: has_more,
          skip_imported_reason: Analytics::Imports.skip_reason(query),
          metric_labels: { percentage: "Percentage" }
        }
      }
    end

    def filtered_pages_relation
      relation = events
      if pattern.present?
        relation = relation.where(Analytics::SqlExpression.lower_matches(page_expression, pattern))
      end
      relation
    end

    def page_expression
      "COALESCE(NULLIF(split_part(ahoy_events.properties->>'page', CHR(63), 1), ''), '(unknown)')"
    end

    def grouped_page_visit_ids(relation, names: nil)
      return {} if names == []

      scoped = relation
      scoped = scoped.where(Analytics::SqlExpression.in_list(page_expression, names)) unless names.nil?
      scoped.group(Arel.sql(page_expression)).pluck(Arel.sql("#{page_expression}, ARRAY_AGG(DISTINCT ahoy_events.visit_id)")).to_h
    end

    def pages_count_first_path?
      return false if goal.present?

      metric = order_by&.first
      !metric.in?(%w[bounce_rate visit_duration time_on_page scroll_depth])
    end

    def seo_payload(paginated:)
      return seo_empty_payload if unsupported_seo_filters?

      analytics_rows = seo_analytics_rows
      gsc_rows = seo_google_search_console_rows
      names = (analytics_rows.keys + gsc_rows.keys).uniq
      names = sort_seo_names(names, analytics_rows, gsc_rows)
      names, has_more = paginate_seo_names(names, paginated:)

      {
        results: names.map { |name| seo_result_row(name, analytics_rows, gsc_rows) },
        metrics: seo_metrics,
        meta: {
          has_more: has_more,
          skip_imported_reason: Analytics::Imports.skip_reason(query),
          metric_labels: seo_metric_labels
        }
      }
    end

    def paginated_entry_payload
      return paginated_entry_summary_payload if visit_summary_eligible?

      base = visits
      present_scope = base.where.not(landing_page: nil).where.not(landing_page: "")
      raw_groups = present_scope.group(:landing_page).pluck(:landing_page, Arel.sql("ARRAY_AGG(ahoy_visits.id)"))
      normalized_groups = Hash.new { |hash, key| hash[key] = [] }
      needs_derivation_ids = []

      raw_groups.each do |landing_page, ids|
        label = Analytics::Urls.normalized_path_only(landing_page)
        label = "(unknown)" if label.blank?
        if Analytics::Pages.internal_entry_label?(label)
          needs_derivation_ids.concat(Array(ids))
        else
          normalized_groups[label] += ids
        end
      end

      missing_ids = base.where("landing_page IS NULL OR landing_page = ''").pluck(:id)
      missing_ids.concat(needs_derivation_ids)
      if missing_ids.any?
        event_rows = Analytics::FactStore.pageviews(
          site: current_site,
          range: range,
          visit_ids: missing_ids,
          order: :asc
        )

        first_page_by_visit = {}
        event_rows.each do |pageview|
          page_name = pageview.page.to_s.split("?").first.presence || "(unknown)"
          previous = first_page_by_visit[pageview.visit_id]
          time_value = pageview.time.respond_to?(:to_time) ? pageview.time.to_time : pageview.time
          if previous.nil? || time_value < previous[0]
            first_page_by_visit[pageview.visit_id] = [ time_value, page_name.to_s ]
          end
        end

        first_page_by_visit.each do |visit_id, (_time, page_name)|
          label = Analytics::Urls.normalized_path_only(page_name)
          label = "(unknown)" if label.blank?
          next if Analytics::Pages.internal_entry_label?(label)

          normalized_groups[label] << visit_id
        end
      end

      normalized_groups.select! { |key, _| key.downcase.include?(search.downcase) } if pattern.present?

      grouped_visit_ids = normalized_groups
      entrances_by_page = grouped_visit_ids.transform_values(&:size)
      all_visit_ids = grouped_visit_ids.values.flatten
      visitors_by_visit = visits.where(id: all_visit_ids).pluck(:id, :visitor_token).to_h
      unique_visitors_by_page = {}
      grouped_visit_ids.each do |name, ids|
        tokens = ids.filter_map { |visit_id| visitors_by_visit[visit_id] }.uniq
        unique_visitors_by_page[name] = tokens.size
      end
      Analytics::Pages.filter_groups!(grouped_visit_ids, unique_visitors_by_page, comparison_names, entrances_by_page)
      total = Analytics::ReportMetrics.percentage_total_visitors(visits)

      if goal.present?
        denominator_counts = Analytics::Pages.goal_denominator_counts(query, mode: mode, search: search)
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

        results = paged_names.map do |name|
          label = name.to_s.presence || "(none)"
          {
            name: label,
            visitors: conversions[name] || 0,
            conversion_rate: Analytics::ReportMetrics.goal_conversion_rate(conversions[name] || 0, denominator_counts[label])
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
        sorted_names =
          if order_by
            metric, = order_by
            case metric
            when "percentage"
              Analytics::Ordering.order_names(
                counts: unique_visitors_by_page,
                metrics_map: unique_visitors_by_page.keys.index_with { |name| { percentage: (unique_visitors_by_page[name].to_f / total) } },
                order_by: order_by
              )
            when "visits"
              Analytics::Ordering.order_names(counts: entrances_by_page, metrics_map: {}, order_by: order_by)
            when "bounce_rate", "visit_duration"
              metrics_all = Analytics::ReportMetrics.calculate_group_metrics(grouped_visit_ids, range, query)
              Analytics::Ordering.order_names(counts: unique_visitors_by_page, metrics_map: unique_visitors_by_page.keys.index_with { |name| metrics_all[name] || {} }, order_by: order_by)
            else
              Analytics::Ordering.order_names(counts: unique_visitors_by_page, metrics_map: {}, order_by: order_by)
            end
          else
            Analytics::Ordering.order_names(counts: unique_visitors_by_page, metrics_map: {}, order_by: nil)
          end

        paged_names, has_more = Analytics::Pagination.paginate_names(sorted_names, limit: limit, page: page)
        page_visit_ids = grouped_visit_ids.slice(*paged_names)
        group_metrics = Analytics::ReportMetrics.calculate_group_metrics(page_visit_ids, range, query)

        results = paged_names.map do |name|
          {
            name: name.to_s.presence || "(none)",
            visitors: unique_visitors_by_page[name] || 0,
            percentage: ((unique_visitors_by_page[name] || 0).to_f / total).round(3),
            visits: entrances_by_page[name] || 0,
            bounce_rate: group_metrics.dig(name, :bounce_rate),
            visit_duration: group_metrics.dig(name, :visit_duration)
          }
        end

        if query.with_imported?
          imported = Analytics::Imports.entry_aggregates(range)
          results.each do |row|
            next unless (counts_row = imported[row[:name]])

            row[:visitors] = row[:visitors].to_i + counts_row[:visitors].to_i
            row[:visits] = row[:visits].to_i + counts_row[:entrances].to_i
          end
        end

        {
          results: results,
          metrics: %i[visitors percentage visits bounce_rate visit_duration],
          meta: {
            has_more: has_more,
            skip_imported_reason: Analytics::Imports.skip_reason(query),
            metric_labels: { visits: "Total Entrances", percentage: "Percentage" }
          }
        }
      end
    end

    def paginated_entry_summary_payload
      relation = filtered_visit_summaries(:entry_page)
      visits_by_page = relation.group(:entry_page).count
      grouped_visit_ids = nil

      if goal.present?
        grouped_visit_ids = grouped_summary_visit_ids(relation, :entry_page)
        unique_visitors_by_page = Analytics::ReportMetrics.unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits)
        Analytics::Pages.filter_groups!(grouped_visit_ids, unique_visitors_by_page, comparison_names, visits_by_page)
      else
        unique_visitors_by_page = relation.group(:entry_page).distinct.count(:visitor_token)
        Analytics::Pages.filter_groups!({}, unique_visitors_by_page, comparison_names, visits_by_page)
      end

      total = Analytics::ReportMetrics.percentage_total_visitors(visits)

      if goal.present?
        denominator_counts = Analytics::Pages.goal_denominator_counts(query, mode: mode, search: search)
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

        results = paged_names.map do |name|
          label = name.to_s.presence || "(none)"
          {
            name: label,
            visitors: conversions[name] || 0,
            conversion_rate: Analytics::ReportMetrics.goal_conversion_rate(conversions[name] || 0, denominator_counts[label])
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
        sorted_names =
          if order_by
            metric, = order_by
            case metric
            when "percentage"
              Analytics::Ordering.order_names(
                counts: unique_visitors_by_page,
                metrics_map: unique_visitors_by_page.keys.index_with { |name| { percentage: (unique_visitors_by_page[name].to_f / total) } },
                order_by: order_by
              )
            when "visits"
              Analytics::Ordering.order_names(counts: visits_by_page, metrics_map: {}, order_by: order_by)
            when "bounce_rate", "visit_duration"
              grouped_visit_ids ||= grouped_summary_visit_ids(relation, :entry_page)
              metrics_all = Analytics::ReportMetrics.calculate_group_metrics(grouped_visit_ids, range, query)
              Analytics::Ordering.order_names(
                counts: unique_visitors_by_page,
                metrics_map: unique_visitors_by_page.keys.index_with { |name| metrics_all[name] || {} },
                order_by: order_by
              )
            else
              Analytics::Ordering.order_names(counts: unique_visitors_by_page, metrics_map: {}, order_by: order_by)
            end
          else
            Analytics::Ordering.order_names(counts: unique_visitors_by_page, metrics_map: {}, order_by: nil)
          end

        paged_names, has_more = Analytics::Pagination.paginate_names(sorted_names, limit: limit, page: page)
        page_visit_ids = grouped_visit_ids ? grouped_visit_ids.slice(*paged_names) : grouped_summary_visit_ids(relation, :entry_page, names: paged_names)
        group_metrics = Analytics::ReportMetrics.calculate_group_metrics(page_visit_ids, range, query)

        results = paged_names.map do |name|
          {
            name: name.to_s.presence || "(none)",
            visitors: unique_visitors_by_page[name] || 0,
            percentage: ((unique_visitors_by_page[name] || 0).to_f / total).round(3),
            visits: visits_by_page[name] || 0,
            bounce_rate: group_metrics.dig(name, :bounce_rate),
            visit_duration: group_metrics.dig(name, :visit_duration)
          }
        end

        if query.with_imported?
          imported = Analytics::Imports.entry_aggregates(range)
          results.each do |row|
            next unless (counts_row = imported[row[:name]])

            row[:visitors] = row[:visitors].to_i + counts_row[:visitors].to_i
            row[:visits] = row[:visits].to_i + counts_row[:entrances].to_i
          end
        end

        {
          results: results,
          metrics: %i[visitors percentage visits bounce_rate visit_duration],
          meta: {
            has_more: has_more,
            skip_imported_reason: Analytics::Imports.skip_reason(query),
            metric_labels: { visits: "Total Entrances", percentage: "Percentage" }
          }
        }
      end
    end

    def paginated_exit_payload
      return paginated_exit_summary_payload if visit_summary_eligible?

      expression = "COALESCE(NULLIF(split_part(ahoy_events.properties->>'page', '?', 1), ''), '(unknown)')"
      event_rows = events.pluck(Arel.sql("visit_id, time, #{expression}"))
      last_page_by_visit = {}

      event_rows.each do |visit_id, time, page_name|
        previous = last_page_by_visit[visit_id]
        time_value = time.respond_to?(:to_time) ? time.to_time : time
        previous_time = previous ? (previous.is_a?(Array) ? previous[0] : previous.first) : nil
        if previous.nil? || time_value > previous_time
          last_page_by_visit[visit_id] = [ time_value, page_name ]
        end
      end

      exit_groups = Hash.new { |hash, key| hash[key] = [] }
      last_page_by_visit.each do |visit_id, (_time, page_name)|
        label = page_name.to_s
        label = "(unknown)" if label.strip.empty?
        exit_groups[label] << visit_id
      end

      exit_groups.select! { |name, _| name.downcase.include?(search.downcase) } if pattern.present?

      exits_by_page = exit_groups.transform_values(&:size)
      all_exit_visit_ids = exit_groups.values.flatten
      visitors_by_visit = visits.where(id: all_exit_visit_ids).pluck(:id, :visitor_token).to_h
      unique_visitors_by_page = {}
      exit_groups.each do |name, ids|
        tokens = ids.filter_map { |visit_id| visitors_by_visit[visit_id] }.uniq
        unique_visitors_by_page[name] = tokens.size
      end
      Analytics::Pages.filter_groups!(exit_groups, unique_visitors_by_page, comparison_names, exits_by_page)
      total = Analytics::ReportMetrics.percentage_total_visitors(visits)

      pageviews_by_page = events.group(Arel.sql(expression)).count
      exit_rate_by_page = {}
      exits_by_page.each do |name, exits|
        pageviews = pageviews_by_page[name] || 0
        exit_rate_by_page[name] = pageviews > 0 ? (exits.to_f / pageviews.to_f * 100.0).round(2) : 0.0
      end
      exit_rate_by_page.select! { |name, _| comparison_names.include?(Analytics::Pages.formatted_name(name)) } if comparison_names.any?

      if goal.present?
        denominator_counts = Analytics::Pages.goal_denominator_counts(query, mode: mode, search: search)
        conversions, conversion_rates = Analytics::ReportMetrics.conversions_and_rates(
          exit_groups,
          visits,
          range,
          query,
          goal,
          denominator_counts: denominator_counts
        )
        sorted_names = Analytics::Ordering.order_names_with_conversions(conversions: conversions, cr: conversion_rates, order_by: order_by)
        paged_names, has_more = Analytics::Pagination.paginate_names(sorted_names, limit: limit, page: page)

        results = paged_names.map do |name|
          label = name.to_s.presence || "(none)"
          {
            name: label,
            visitors: conversions[name] || 0,
            conversion_rate: Analytics::ReportMetrics.goal_conversion_rate(conversions[name] || 0, denominator_counts[label])
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
        sorted_names =
          if order_by
            metric, = order_by
            case metric
            when "percentage"
              Analytics::Ordering.order_names(
                counts: unique_visitors_by_page,
                metrics_map: unique_visitors_by_page.keys.index_with { |name| { percentage: (unique_visitors_by_page[name].to_f / total) } },
                order_by: order_by
              )
            when "visits"
              Analytics::Ordering.order_names(counts: exits_by_page, metrics_map: {}, order_by: order_by)
            when "exit_rate"
              Analytics::Ordering.order_names(counts: unique_visitors_by_page, metrics_map: exit_rate_by_page.transform_values { |value| { exit_rate: value } }, order_by: order_by)
            else
              Analytics::Ordering.order_names(counts: unique_visitors_by_page, metrics_map: {}, order_by: order_by)
            end
          else
            Analytics::Ordering.order_names(counts: unique_visitors_by_page, metrics_map: {}, order_by: nil)
          end

        paged_names, has_more = Analytics::Pagination.paginate_names(sorted_names, limit: limit, page: page)
        results = paged_names.map do |name|
          {
            name: name.to_s.presence || "(none)",
            visitors: unique_visitors_by_page[name] || 0,
            percentage: ((unique_visitors_by_page[name] || 0).to_f / total).round(3),
            visits: exits_by_page[name] || 0,
            exit_rate: exit_rate_by_page[name] || 0.0
          }
        end

        if query.with_imported?
          imported = Analytics::Imports.exit_aggregates(range)
          results.each do |row|
            next unless (counts_row = imported[row[:name]])

            total_exits = row[:visits].to_i + counts_row[:exits].to_i
            total_pageviews = (pageviews_by_page[row[:name]] || 0) + counts_row[:pageviews].to_i
            row[:visitors] = row[:visitors].to_i + counts_row[:visitors].to_i
            row[:visits] = total_exits
            row[:exit_rate] = total_pageviews.positive? ? (total_exits.to_f / total_pageviews.to_f * 100.0).round(2) : row[:exit_rate]
          end
        end

        {
          results: results,
          metrics: %i[visitors percentage visits exit_rate],
          meta: {
            has_more: has_more,
            skip_imported_reason: Analytics::Imports.skip_reason(query),
            metric_labels: { visits: "Total Exits", exitRate: "Exit Rate", percentage: "Percentage" }
          }
        }
      end
    end

    def paginated_exit_summary_payload
      relation = filtered_visit_summaries(:exit_page, require_pageviews: true)
      grouped_visit_ids = nil

      if goal.present?
        grouped_visit_ids = grouped_summary_visit_ids(relation, :exit_page)
        unique_visitors_by_page = Analytics::ReportMetrics.unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits)
        exits_by_page = grouped_visit_ids.transform_values(&:size)
        Analytics::Pages.filter_groups!(grouped_visit_ids, unique_visitors_by_page, comparison_names, exits_by_page)
      else
        unique_visitors_by_page = relation.group(:exit_page).distinct.count(:visitor_token)
        exits_by_page = relation.group(:exit_page).count
        Analytics::Pages.filter_groups!({}, unique_visitors_by_page, comparison_names, exits_by_page)
      end

      total = Analytics::ReportMetrics.percentage_total_visitors(visits)
      pageviews_by_page = events.group(Arel.sql(page_expression)).count
      exit_rate_by_page = {}
      exits_by_page.each do |name, exits|
        pageviews = pageviews_by_page[name] || 0
        exit_rate_by_page[name] = pageviews > 0 ? (exits.to_f / pageviews.to_f * 100.0).round(2) : 0.0
      end
      exit_rate_by_page.select! { |name, _| comparison_names.include?(Analytics::Pages.formatted_name(name)) } if comparison_names.any?

      if goal.present?
        denominator_counts = Analytics::Pages.goal_denominator_counts(query, mode: mode, search: search)
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

        results = paged_names.map do |name|
          label = name.to_s.presence || "(none)"
          {
            name: label,
            visitors: conversions[name] || 0,
            conversion_rate: Analytics::ReportMetrics.goal_conversion_rate(conversions[name] || 0, denominator_counts[label])
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
        sorted_names =
          if order_by
            metric, = order_by
            case metric
            when "percentage"
              Analytics::Ordering.order_names(
                counts: unique_visitors_by_page,
                metrics_map: unique_visitors_by_page.keys.index_with { |name| { percentage: (unique_visitors_by_page[name].to_f / total) } },
                order_by: order_by
              )
            when "visits"
              Analytics::Ordering.order_names(counts: exits_by_page, metrics_map: {}, order_by: order_by)
            when "exit_rate"
              Analytics::Ordering.order_names(
                counts: unique_visitors_by_page,
                metrics_map: exit_rate_by_page.transform_values { |value| { exit_rate: value } },
                order_by: order_by
              )
            else
              Analytics::Ordering.order_names(counts: unique_visitors_by_page, metrics_map: {}, order_by: order_by)
            end
          else
            Analytics::Ordering.order_names(counts: unique_visitors_by_page, metrics_map: {}, order_by: nil)
          end

        paged_names, has_more = Analytics::Pagination.paginate_names(sorted_names, limit: limit, page: page)
        results = paged_names.map do |name|
          {
            name: name.to_s.presence || "(none)",
            visitors: unique_visitors_by_page[name] || 0,
            percentage: ((unique_visitors_by_page[name] || 0).to_f / total).round(3),
            visits: exits_by_page[name] || 0,
            exit_rate: exit_rate_by_page[name] || 0.0
          }
        end

        if query.with_imported?
          imported = Analytics::Imports.exit_aggregates(range)
          results.each do |row|
            next unless (counts_row = imported[row[:name]])

            total_exits = row[:visits].to_i + counts_row[:exits].to_i
            total_pageviews = (pageviews_by_page[row[:name]] || 0) + counts_row[:pageviews].to_i
            row[:visitors] = row[:visitors].to_i + counts_row[:visitors].to_i
            row[:visits] = total_exits
            row[:exit_rate] = total_pageviews.positive? ? (total_exits.to_f / total_pageviews.to_f * 100.0).round(2) : row[:exit_rate]
          end
        end

        {
          results: results,
          metrics: %i[visitors percentage visits exit_rate],
          meta: {
            has_more: has_more,
            skip_imported_reason: Analytics::Imports.skip_reason(query),
            metric_labels: { visits: "Total Exits", exitRate: "Exit Rate", percentage: "Percentage" }
          }
        }
      end
    end

    def full_pages_payload
      return full_pages_rollup_payload if page_rollup_eligible?

      expression = "COALESCE(NULLIF(split_part(ahoy_events.properties->>'page', '?', 1), ''), '(unknown)')"
      counts = events.group(Arel.sql(expression)).distinct.count(:visitor_token)
      if counts.empty?
        raw = visits.where.not(landing_page: nil).group(:landing_page).distinct.count(:visitor_token)
        counts = Hash.new(0)
        raw.each do |landing_page, visitors_count|
          label = Analytics::Urls.normalized_path_and_query(landing_page)
          label = "(unknown)" if label.blank?
          next if Analytics::Pages.internal_entry_label?(label)

          counts[label] += visitors_count
        end
      end

      if query.with_imported?
        Analytics::Imports.pages_aggregates(range).each do |name, counts_row|
          counts[name] = counts[name].to_i + counts_row[:visitors].to_i
        end
      end

      total = Analytics::ReportMetrics.percentage_total_visitors(visits)
      rows = counts.sort_by { |_, visitors_count| -visitors_count }.map do |name, visitors_count|
        {
          name: name.to_s.presence || "(none)",
          visitors: visitors_count,
          percentage: (visitors_count.to_f / total).round(3)
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

    def full_pages_rollup_payload
      counts = Analytics::SitePageHourlyRollup.counts_for(range: range, site: current_site, search: search)

      if query.with_imported?
        Analytics::Imports.pages_aggregates(range).each do |name, counts_row|
          counts[name] = counts[name].to_i + counts_row[:visitors].to_i
        end
      end

      total = Analytics::ReportMetrics.percentage_total_visitors(visits)
      rows = counts.sort_by { |_, visitors_count| -visitors_count }.map do |name, visitors_count|
        {
          name: name.to_s.presence || "(none)",
          visitors: visitors_count,
          percentage: (visitors_count.to_f / total).round(3)
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

    def full_entry_payload
      return full_entry_summary_payload if visit_summary_eligible?

      counts = Hash.new(0)
      present_scope = visits.where.not(landing_page: nil).where.not(landing_page: "")
      present = present_scope.group(:landing_page).distinct.count(:visitor_token)
      needs_derivation_ids = []

      present_scope.group(:landing_page).pluck(:landing_page, Arel.sql("ARRAY_AGG(ahoy_visits.id)")).each do |landing_page, ids|
        label = Analytics::Urls.normalized_path_only(landing_page)
        label = "(unknown)" if label.blank?
        needs_derivation_ids.concat(Array(ids)) if Analytics::Pages.internal_entry_label?(label)
      end

      present.each do |landing_page, visitors_count|
        label = Analytics::Urls.normalized_path_only(landing_page)
        label = "(unknown)" if label.blank?
        next if Analytics::Pages.internal_entry_label?(label)

        counts[label] += visitors_count
      end

      missing_ids = visits.where("landing_page IS NULL OR landing_page = ''").pluck(:id)
      missing_ids.concat(needs_derivation_ids)
      if missing_ids.any?
        event_rows = Analytics::FactStore.pageviews(
          site: current_site,
          range: range,
          visit_ids: missing_ids,
          order: :asc
        )

        first_page_by_visit = {}
        event_rows.each do |pageview|
          previous = first_page_by_visit[pageview.visit_id]
          time_value = pageview.time.respond_to?(:to_time) ? pageview.time.to_time : pageview.time
          if previous.nil? || time_value < previous[0]
            first_page_by_visit[pageview.visit_id] = [ time_value, pageview.page.to_s.presence || "(unknown)" ]
          end
        end

        visitors_by_visit = visits.where(id: first_page_by_visit.keys).pluck(:id, :visitor_token).to_h
        per_label_visitors = Hash.new { |hash, key| hash[key] = Set.new }
        first_page_by_visit.each do |visit_id, (_time, page_name)|
          label = Analytics::Urls.normalized_path_only(page_name)
          label = "(unknown)" if label.blank?
          next if Analytics::Pages.internal_entry_label?(label)

          token = visitors_by_visit[visit_id]
          per_label_visitors[label] << token if token.present?
        end
        per_label_visitors.each { |label, tokens| counts[label] += tokens.size }
      end

      if query.with_imported?
        Analytics::Imports.entry_aggregates(range).each do |name, counts_row|
          counts[name] = counts[name].to_i + counts_row[:visitors].to_i
        end
      end

      total = Analytics::ReportMetrics.percentage_total_visitors(visits)
      rows = counts.sort_by { |_, visitors_count| -visitors_count }.map do |name, visitors_count|
        {
          name: name.to_s.presence || "(none)",
          visitors: visitors_count,
          percentage: (visitors_count.to_f / total).round(3)
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

    def full_entry_summary_payload
      counts = filtered_visit_summaries(:entry_page).group(:entry_page).distinct.count(:visitor_token)

      if query.with_imported?
        Analytics::Imports.entry_aggregates(range).each do |name, counts_row|
          counts[name] = counts[name].to_i + counts_row[:visitors].to_i
        end
      end

      total = Analytics::ReportMetrics.percentage_total_visitors(visits)
      rows = counts.sort_by { |_, visitors_count| -visitors_count }.map do |name, visitors_count|
        {
          name: name.to_s.presence || "(none)",
          visitors: visitors_count,
          percentage: (visitors_count.to_f / total).round(3)
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

    def unsupported_seo_filters?
      Analytics::GoogleSearchConsole.unsupported_pages_filters?(query)
    end

    def seo_metrics
      goal.present? ? SEO_GOAL_METRICS : SEO_METRICS
    end

    def seo_metric_labels
      labels = {}
      if goal.present?
        labels[:visitors] = "Conversions"
        labels[:conversionRate] = "Conversion Rate"
      end
      labels
    end

    def seo_empty_payload
      {
        results: [],
        metrics: seo_metrics,
        meta: {
          has_more: false,
          skip_imported_reason: Analytics::Imports.skip_reason(query),
          metric_labels: seo_metric_labels
        }
      }
    end

    def seo_analytics_rows
      if seo_page_rollup_eligible?
        counts = Analytics::SitePageHourlyRollup.counts_for(range: range, site: current_site, search: search)
        pageviews_by_page = Analytics::SitePageHourlyRollup.pageviews_for(range: range, site: current_site, search: search)
        Analytics::Pages.filter_groups!({}, counts, comparison_names, pageviews_by_page)

        counts.each_with_object({}) do |(name, visitors), result|
          label = name.to_s.presence || "(none)"
          result[label] = {
            visitors: visitors.to_i,
            pageviews: pageviews_by_page[name].to_i
          }
        end
      else
        expression = "COALESCE(NULLIF(split_part(ahoy_events.properties->>'page', CHR(63), 1), ''), '(unknown)')"
        relation = events

        if pattern.present?
          search_clause = "LOWER(COALESCE(NULLIF(split_part(ahoy_events.properties->>'page', CHR(63), 1), ''), '(unknown)')) LIKE ?"
          relation = relation.where(search_clause, pattern)
        end

        grouped_visit_ids = relation.group(Arel.sql(expression)).pluck(Arel.sql("#{expression}, ARRAY_AGG(DISTINCT ahoy_events.visit_id)")).to_h
        counts = Analytics::ReportMetrics.unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits)
        pageviews_by_page = relation.group(Arel.sql(expression)).count
        Analytics::Pages.filter_groups!(grouped_visit_ids, counts, comparison_names, pageviews_by_page)

        if goal.present?
          denominator_counts = Analytics::Pages.goal_denominator_counts(query, mode: "pages", search: search)
          conversions, = Analytics::ReportMetrics.conversions_and_rates(
            grouped_visit_ids,
            visits,
            range,
            query,
            goal,
            denominator_counts: denominator_counts
          )

          grouped_visit_ids.each_with_object({}) do |(name, _ids), result|
            label = name.to_s.presence || "(none)"
            result[label] = {
              visitors: conversions[name] || 0,
              conversion_rate: Analytics::ReportMetrics.goal_conversion_rate(
                conversions[name] || 0,
                denominator_counts[label]
              )
            }
          end
        else
          grouped_visit_ids.each_with_object({}) do |(name, _ids), result|
            label = name.to_s.presence || "(none)"
            result[label] = {
              visitors: counts[name] || 0,
              pageviews: pageviews_by_page[name] || 0
            }
          end
        end
      end
    end

    def seo_google_search_console_rows
      return {} if ::Analytics::Current.site.blank?

      rows = seo_google_search_console_relation.to_a
      rows.each_with_object({}) do |row, result|
        name = row.name.to_s.presence || "(unknown)"
        impressions = row.impressions.to_i

        result[name] = {
          clicks: row.clicks.to_i,
          impressions: impressions,
          ctr: impressions.positive? ? ((row.clicks.to_f / impressions) * 100.0).round(1) : 0.0,
          position: impressions.positive? ? (row.position_impressions_sum.to_f / impressions).round(1) : 0.0
        }
      end
    end

    def seo_google_search_console_relation
      relation = Analytics::GoogleSearchConsole::QueryRow
        .for_site(::Analytics::Current.site)
        .for_search_type(Analytics::GoogleSearchConsole::Syncer::DEFAULT_SEARCH_TYPE)
        .within_dates(range.begin.to_date, range.end.to_date)

      if (country_value = normalized_country_filter(query.filter_value(:country))).present?
        relation = relation.where(country: country_value)
      end

      if (page_value = normalized_page_filter(query.filter_value(:page))).present?
        relation = relation.where(page: page_value)
      end

      if pattern.present?
        relation = relation.where("page ILIKE ?", pattern)
      end

      relation
        .group(:page)
        .select(
          "page AS name",
          "SUM(clicks) AS clicks",
          "SUM(impressions) AS impressions",
          "SUM(position_impressions_sum) AS position_impressions_sum"
        )
        .yield_self do |scope|
          if comparison_names.any?
            scope.having(page: comparison_names)
          else
            scope
          end
        end
    end

    def seo_result_row(name, analytics_rows, gsc_rows)
      analytics = analytics_rows[name] || {}
      gsc = gsc_rows[name] || {}

      row = {
        name: name,
        clicks: gsc[:clicks].to_i,
        impressions: gsc[:impressions].to_i,
        ctr: gsc[:ctr].to_f,
        position: gsc[:position].to_f,
        visitors: analytics[:visitors].to_i
      }

      if goal.present?
        row[:conversion_rate] = analytics[:conversion_rate]
      else
        row[:pageviews] = analytics[:pageviews].to_i
      end

      row
    end

    def sort_seo_names(names, analytics_rows, gsc_rows)
      metric, direction = normalized_seo_order_by
      sorted = names.sort_by do |name|
        row = seo_result_row(name, analytics_rows, gsc_rows)
        value = row.fetch(metric.to_sym) { row.fetch(metric.to_s, 0) }
        [ value_for_seo_sort(value, metric), name.to_s.downcase ]
      end

      direction == "desc" ? sorted.reverse : sorted
    end

    def normalized_seo_order_by
      metric, direction = Array(order_by)
      allowed_metrics = seo_metrics.map(&:to_s) + [ "name" ]
      normalized_metric = metric.to_s.presence
      normalized_metric = "clicks" unless allowed_metrics.include?(normalized_metric)
      normalized_direction = normalized_metric == "name" ? "asc" : "desc"
      normalized_direction = direction.to_s if direction.to_s.in?(%w[asc desc])
      [ normalized_metric, normalized_direction ]
    end

    def value_for_seo_sort(value, metric)
      return value.to_s.downcase if metric == "name"

      value.to_f
    end

    def paginate_seo_names(names, paginated:)
      return [ names, false ] unless paginated

      paged_names = names.slice((page - 1) * limit, limit) || []
      has_more = names.length > ((page - 1) * limit + paged_names.length)
      [ paged_names, has_more ]
    end

    def normalized_country_filter(country_value)
      return if country_value.blank?

      alpha2 = Ahoy::Visit.normalize_country_code(country_value)
      ISO3166::Country[alpha2]&.alpha3
    end

    def normalized_page_filter(page_value)
      value = page_value.to_s.strip
      return if value.blank?

      Analytics::Urls.normalized_path_only(value).presence || value
    end

    def full_exit_payload
      return full_exit_summary_payload if visit_summary_eligible?

      expression = "COALESCE(ahoy_events.properties->>'page', '(unknown)')"
      event_rows = Analytics::VisitScope.pageviews(range, query).pluck(Arel.sql("visit_id, time, #{expression}"))
      last_page_by_visit = {}

      event_rows.each do |visit_id, time, page_name|
        previous = last_page_by_visit[visit_id]
        time_value = time.respond_to?(:to_time) ? time.to_time : time
        previous_time = previous ? (previous.is_a?(Array) ? previous[0] : previous.first) : nil
        if previous.nil? || time_value > previous_time
          last_page_by_visit[visit_id] = [ time_value, page_name ]
        end
      end

      exit_groups = Hash.new { |hash, key| hash[key] = [] }
      last_page_by_visit.each do |visit_id, (_time, page_name)|
        exit_groups[page_name.to_s.presence || "(unknown)"] << visit_id
      end

      all_ids = exit_groups.values.flatten
      visitor_map = visits.where(id: all_ids).pluck(:id, :visitor_token).to_h
      unique_counts = exit_groups.transform_values { |ids| ids.filter_map { |visit_id| visitor_map[visit_id] }.uniq.size }
      total = Analytics::ReportMetrics.percentage_total_visitors(visits)
      rows = unique_counts.sort_by { |_, visitors_count| -visitors_count }.map do |name, visitors_count|
        {
          name: name.to_s.presence || "(none)",
          visitors: visitors_count,
          percentage: (visitors_count.to_f / total).round(3)
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

    def full_exit_summary_payload
      counts = filtered_visit_summaries(:exit_page, require_pageviews: true).group(:exit_page).distinct.count(:visitor_token)
      total = Analytics::ReportMetrics.percentage_total_visitors(visits)
      rows = counts.sort_by { |_, visitors_count| -visitors_count }.map do |name, visitors_count|
        {
          name: name.to_s.presence || "(none)",
          visitors: visitors_count,
          percentage: (visitors_count.to_f / total).round(3)
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

    def current_site
      Analytics::Current.site_or_default
    end

    def page_rollup_eligible?
      return false unless mode == "pages"
      return false unless site_page_rollup_eligible?

      metric = order_by&.first
      return false if metric.in?(%w[bounce_rate visit_duration time_on_page scroll_depth])

      true
    end

    def seo_page_rollup_eligible?
      return false unless mode == "seo"
      return false unless site_page_rollup_eligible?

      true
    end

    def site_page_rollup_eligible?
      return false if goal.present?
      return false unless query.filter_dimensions.empty?
      return false unless query.advanced_filters.empty?
      return false unless Analytics::SitePageHourlyRollup.available?

      Analytics::SitePageHourlyRollup.usable_for?(range: range, site: current_site)
    end

    def visit_summary_eligible?
      return false unless Analytics::VisitSummary.available?

      total_visits = visits.count
      return false if total_visits.zero?

      Analytics::VisitSummary.where(visit_id: visits.select(:id)).count == total_visits
    rescue StandardError
      false
    end

    def filtered_visit_summaries(column, require_pageviews: false)
      relation = Analytics::VisitSummary.where(visit_id: visits.select(:id))
      relation = relation.where.not(column => "")
      relation = relation.where(summary_column_matches(column, pattern)) if pattern.present?
      relation = relation.where("pageviews_count > 0") if require_pageviews
      relation
    end

    def grouped_summary_visit_ids(relation, column, names: nil)
      return {} if names == []

      scoped = relation
      scoped = scoped.where(column => names) unless names.nil?
      scoped.group(column).pluck(Arel.sql("#{column}, ARRAY_AGG(visit_id)")).to_h
    end

    def summary_column_matches(column, pattern)
      Arel::Nodes::NamedFunction.new("LOWER", [ Analytics::VisitSummary.arel_table[column.to_sym] ]).matches(pattern)
    end
end
