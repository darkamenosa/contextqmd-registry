# frozen_string_literal: true

class Analytics::PagesDatasetQuery::Postgres
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
      when "pages" then paginated_pages_payload
      when "entry" then paginated_entry_payload
      else
        paginated_exit_payload
      end
    end

    def full_payload
      case mode
      when "pages" then full_pages_payload
      when "entry" then full_entry_payload
      else
        full_exit_payload
      end
    end

    def paginated_pages_payload
      expression = "COALESCE(NULLIF(split_part(ahoy_events.properties->>'page', CHR(63), 1), ''), '(unknown)')"
      relation = events
      if pattern.present?
        search_clause = "LOWER(COALESCE(NULLIF(split_part(ahoy_events.properties->>'page', CHR(63), 1), ''), '(unknown)')) LIKE ?"
        relation = relation.where(search_clause, pattern)
      end

      grouped_visit_ids = relation.group(Arel.sql(expression)).pluck(Arel.sql("#{expression}, ARRAY_AGG(DISTINCT ahoy_events.visit_id)")).to_h
      counts = Analytics::ReportMetrics.unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits)
      pageviews_by_page = events.group(Arel.sql(expression)).count
      Analytics::Pages.filter_groups!(grouped_visit_ids, counts, comparison_names, pageviews_by_page)
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
        page_visit_ids = grouped_visit_ids.slice(*paged_names)
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

    def paginated_entry_payload
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
        event_rows = Ahoy::Event
          .where(name: "pageview", visit_id: missing_ids, time: range)
          .pluck(Arel.sql("visit_id, time, COALESCE(NULLIF(split_part(ahoy_events.properties->>'page', '?', 1), ''), '(unknown)')"))

        first_page_by_visit = {}
        event_rows.each do |visit_id, time, page_name|
          previous = first_page_by_visit[visit_id]
          time_value = time.respond_to?(:to_time) ? time.to_time : time
          if previous.nil? || time_value < previous[0]
            first_page_by_visit[visit_id] = [ time_value, page_name.to_s ]
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

    def paginated_exit_payload
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

    def full_pages_payload
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

    def full_entry_payload
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
        event_rows = Ahoy::Event
          .where(name: "pageview", visit_id: missing_ids, time: range)
          .pluck(Arel.sql("visit_id, time, COALESCE(ahoy_events.properties->>'page', '(unknown)')"))

        first_page_by_visit = {}
        event_rows.each do |visit_id, time, page_name|
          previous = first_page_by_visit[visit_id]
          time_value = time.respond_to?(:to_time) ? time.to_time : time
          if previous.nil? || time_value < previous[0]
            first_page_by_visit[visit_id] = [ time_value, page_name.to_s ]
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

    def full_exit_payload
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
end
