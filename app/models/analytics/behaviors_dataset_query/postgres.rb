# frozen_string_literal: true

class Analytics::BehaviorsDatasetQuery::Postgres
  def initialize(query:, limit:, page:, search:, order_by:)
    @query = Analytics::Query.wrap(query)
    @limit = limit
    @page = page
    @search = search
    @order_by = order_by
  end

  def payload
    case mode
    when "props"
      props_payload
    when "funnels"
      funnels_payload
    else
      conversions_payload
    end
  end

  private
    attr_reader :query, :limit, :page, :search, :order_by

    def mode
      (query.mode || "conversions").to_s
    end

    def range
      @range ||= begin
        raw_range, = Analytics::Ranges.range_and_interval_for(query.time_range_key, nil, query)
        raw_range
      end
    end

    def comparison_names
      query.comparison_filter_names
    end

    def props_payload
      base_query =
        if query.goal_filter_applied?
          query.without_goal
        else
          query.without_goal_or_properties(property_filter: ->(key) { Analytics::Properties.filter_key?(key) })
        end

      visits = Analytics::VisitScope.visits(range, base_query)
      events = property_events_scope(visits)
      property_keys = Analytics::Properties.available_keys(events)
      active_property = query.property.presence
      active_property = property_keys.first unless property_keys.include?(active_property)

      if active_property.blank?
        return {
          list: {
            results: [],
            metrics: query.goal_filter_applied? ? %i[visitors events conversion_rate] : %i[visitors events percentage],
            meta: {
              has_more: false,
              skip_imported_reason: Analytics::Imports.skip_reason(query),
              metric_labels: { events: "Events" }
            }
          },
          property_keys: [],
          active_property: nil,
          goal_highlighted: nil
        }
      end

      value_expr = Analytics::Properties.event_property_value(active_property)
      property_events = events.where(Analytics::Properties.event_property_exists(active_property))
      unless query.goal_filter_applied?
        property_events = Analytics::Properties.apply_event_filters(property_events, query.filter_clauses)
      end
      if search.present?
        property_events = property_events.where(
          Analytics::Properties.event_property_value_lower(active_property).matches(Analytics::Search.contains_pattern(search))
        )
      end

      visitor_counts = property_events.group(value_expr).count("DISTINCT ahoy_visits.visitor_token")
      total_counts = property_events.group(value_expr).count
      if comparison_names.any?
        visitor_counts.select! { |name, _| comparison_names.include?(name.to_s) }
        total_counts.select! { |name, _| comparison_names.include?(name.to_s) }
      end

      metrics_map =
        if query.goal_filter_applied?
          total_uniques = Analytics::VisitScope.visits(
            range,
            query_without_goal_or_properties
          ).select(:visitor_token).distinct.count
          total_uniques = 1 if total_uniques <= 0
          visitor_counts.keys.index_with do |name|
            {
              events: total_counts[name].to_i,
              conversion_rate: ((visitor_counts[name].to_f / total_uniques.to_f) * 100.0).round(2)
            }
          end
        else
          total_visitors = property_events.distinct.count("ahoy_visits.visitor_token")
          total_visitors = 1 if total_visitors <= 0
          visitor_counts.keys.index_with do |name|
            {
              events: total_counts[name].to_i,
              percentage: (visitor_counts[name].to_f / total_visitors).round(3)
            }
          end
        end

      sorted_names = Analytics::Ordering.order_names(counts: visitor_counts, metrics_map: metrics_map, order_by: order_by)

      if limit && page
        paged_names, has_more = Analytics::Pagination.paginate_names(sorted_names, limit: limit, page: page)
        rows = paged_names.map do |name|
          visitors = visitor_counts[name].to_i
          row = { name: name.to_s, visitors: visitors, events: total_counts[name].to_i }
          if query.goal_filter_applied?
            row[:conversion_rate] = metrics_map.dig(name, :conversion_rate)
          else
            row[:percentage] = metrics_map.dig(name, :percentage)
          end
          row
        end

        {
          list: {
            results: rows,
            metrics: query.goal_filter_applied? ? %i[visitors events conversion_rate] : %i[visitors events percentage],
            meta: {
              has_more: has_more,
              skip_imported_reason: Analytics::Imports.skip_reason(query),
              metric_labels: { events: "Events" }
            }
          },
          property_keys: property_keys,
          active_property: active_property,
          goal_highlighted: nil
        }
      else
        rows = sorted_names.map do |name|
          visitors = visitor_counts[name].to_i
          row = { name: name.to_s, visitors: visitors, events: total_counts[name].to_i }
          if query.goal_filter_applied?
            row[:conversion_rate] = metrics_map.dig(name, :conversion_rate)
          else
            row[:percentage] = metrics_map.dig(name, :percentage)
          end
          row
        end

        {
          list: {
            results: rows,
            metrics: query.goal_filter_applied? ? %i[visitors events conversion_rate] : %i[visitors events percentage],
            meta: {
              has_more: false,
              skip_imported_reason: Analytics::Imports.skip_reason(query),
              metric_labels: { events: "Events" }
            }
          },
          property_keys: property_keys,
          active_property: active_property,
          goal_highlighted: nil
        }
      end
    end

    def property_events_scope(visits)
      events = Ahoy::Event
        .joins(:visit)
        .merge(visits)
        .where(time: range)
        .where.not(properties: [ nil, {} ])

      if query.goal_filter_applied?
        if (goal = Analytics::Goals.configured(query.filter_value(:goal)))
          Analytics::Goals.apply(events, goal)
        else
          events.where(name: query.filter_value(:goal))
        end
      else
        events.where.not(name: [ "pageview", "engagement" ])
      end
    end

    def query_without_goal_or_properties
      @query_without_goal_or_properties ||= query.without_goal_or_properties(
        property_filter: ->(key) { Analytics::Properties.filter_key?(key) }
      )
    end

    def funnels_payload
      visits = Analytics::VisitScope.visits(range, query)
      names = Funnel.order(:name).pluck(:name)
      active_name = query.funnel.presence || names.first
      return { funnels: names, active: { name: "", steps: [] } } if active_name.blank?

      funnel = Funnel.find_by(name: active_name)
      return { funnels: names, active: { name: "", steps: [] } } unless funnel

      event_rows = Ahoy::Event
        .joins(:visit)
        .merge(visits)
        .where(time: range)
        .pluck(Arel.sql("ahoy_events.visit_id, ahoy_events.time, ahoy_events.name, COALESCE(ahoy_events.properties->>'page', '')"))

      by_visit = Hash.new { |hash, key| hash[key] = [] }
      event_rows.each do |visit_id, time, name, page|
        by_visit[visit_id] << [ (time.respond_to?(:to_time) ? time.to_time : time), name.to_s, page.to_s ]
      end
      by_visit.each_value { |events| events.sort_by!(&:first) }

      token_by_visit = visits.pluck(:id, :visitor_token).to_h
      total_visitors = visits.distinct.count(:visitor_token)

      sets = Array.new(funnel.steps.length) { Set.new }
      by_visit.each do |visit_id, events|
        next if events.empty?

        step_index = 0
        current_time = Time.at(0)
        while step_index < funnel.steps.length
          step = funnel.steps[step_index].to_h.with_indifferent_access
          step_type = step[:type].to_s
          match = step[:match].to_s
          value = step[:value].to_s
          found = false

          events.each do |time, name, page|
            next if time < current_time

            matched = case step_type
            when "event"
              match == "equals" ? (name == value) : name.include?(value)
            when "page"
              match == "contains" ? page.include?(value) : page == value
            else
              false
            end

            next unless matched

            current_time = time
            found = true
            break
          end

          break unless found

          token = token_by_visit[visit_id]
          sets[step_index] << token if token.present?
          step_index += 1
        end
      end

      entering_visitors = sets.first&.size.to_i
      never_entering_visitors = [ total_visitors - entering_visitors, 0 ].max
      entering_visitors_percentage =
        if total_visitors.positive?
          ((entering_visitors.to_f / total_visitors.to_f) * 100.0).round(2)
        else
          0.0
        end
      never_entering_visitors_percentage =
        if total_visitors.positive?
          ((never_entering_visitors.to_f / total_visitors.to_f) * 100.0).round(2)
        else
          0.0
        end

      steps = funnel.steps.each_with_index.map do |step, index|
        step = step.with_indifferent_access
        visitors = sets[index].size
        previous_visitors = index.zero? ? entering_visitors : sets[index - 1].size
        dropoff =
          if index.zero?
            never_entering_visitors
          else
            [ previous_visitors - visitors, 0 ].max
          end
        conversion_rate =
          if entering_visitors.positive?
            ((visitors.to_f / entering_visitors.to_f) * 100.0).round(2)
          else
            0.0
          end
        conversion_rate_step =
          if index.zero?
            entering_visitors_percentage
          elsif previous_visitors.positive?
            ((visitors.to_f / previous_visitors.to_f) * 100.0).round(2)
          else
            0.0
          end
        dropoff_percentage =
          if index.zero?
            never_entering_visitors_percentage
          elsif previous_visitors.positive?
            ((dropoff.to_f / previous_visitors.to_f) * 100.0).round(2)
          else
            0.0
          end
        label = step[:name] || step[:type].to_s.capitalize

        {
          name: label,
          visitors: visitors,
          conversion_rate: conversion_rate,
          conversion_rate_step: conversion_rate_step,
          dropoff: dropoff,
          dropoff_percentage: dropoff_percentage
        }
      end

      overall_conversion_rate = steps.last&.dig(:conversion_rate).to_f.round(2)

      {
        funnels: names,
        active: {
          name: funnel.name,
          conversion_rate: overall_conversion_rate,
          entering_visitors: entering_visitors,
          entering_visitors_percentage: entering_visitors_percentage,
          never_entering_visitors: never_entering_visitors,
          never_entering_visitors_percentage: never_entering_visitors_percentage,
          steps: steps
        }
      }
    end

    def conversions_payload
      names = Analytics::Goals.available_names
      names = names.select { |name| comparison_names.include?(name.to_s) } if comparison_names.any?

      rows = names.map do |goal_name|
        totals = Analytics::ReportMetrics.goal_metric_totals(
          range,
          query.with_filter(:goal, goal_name.to_s)
        )

        {
          name: goal_name.to_s,
          uniques: totals[:unique_conversions],
          total: totals[:total_conversions],
          conversion_rate: totals[:conversion_rate]
        }
      end

      if search.present?
        needle = search.downcase
        rows.select! { |row| row[:name].downcase.include?(needle) }
      end

      rows =
        if order_by
          metric, dir = order_by
          dir = (dir&.downcase == "asc") ? 1 : -1
          rows = rows.sort_by do |row|
            case metric
            when "name"
              row[:name].downcase
            when "total"
              row[:total].to_i
            when "conversion_rate"
              row[:conversion_rate] || -Float::INFINITY
            else
              row[:uniques].to_i
            end
          end
          dir == -1 ? rows.reverse : rows
        else
          rows.sort_by { |row| [ -row[:uniques].to_i, row[:name].downcase ] }
        end

      if limit && page
        window, has_more = Analytics::Pagination.paginate_names(rows, limit: limit, page: page)
        {
          results: window,
          metrics: %i[uniques total conversion_rate],
          meta: { has_more: has_more, skip_imported_reason: Analytics::Imports.skip_reason(query) },
          goal_highlighted: nil
        }
      else
        {
          results: rows,
          metrics: %i[uniques total conversion_rate],
          meta: { has_more: false, skip_imported_reason: Analytics::Imports.skip_reason(query) }
        }
      end
    end
end
