# frozen_string_literal: true

module Analytics::Pages
  class << self
    def time_on_page_and_scroll(range, query_or_filters, grouped_visit_ids, advanced_filters: [])
      return {} if grouped_visit_ids.blank?

      query =
        if query_or_filters.is_a?(Analytics::Query)
          query_or_filters
        else
          Analytics::Query.new(filters: query_or_filters, advanced_filters: advanced_filters)
        end

      names = grouped_visit_ids.keys
      all_visit_ids = grouped_visit_ids.values.flatten.uniq
      return {} if all_visit_ids.empty?

      events_scope = Analytics::VisitScope.pageviews(range, query)
      event_rows = events_scope.where(visit_id: all_visit_ids)
        .pluck(Arel.sql("visit_id, time, COALESCE(NULLIF(split_part(ahoy_events.properties->>'page', '?', 1), ''), '(unknown)')"))

      by_visit = Hash.new { |hash, key| hash[key] = [] }
      event_rows.each { |visit_id, time, page| by_visit[visit_id] << [ (time.respond_to?(:to_time) ? time.to_time : time), page ] }
      by_visit.each_value { |events| events.sort_by!(&:first) }

      legacy_sum = Hash.new(0.0)
      legacy_count = Hash.new(0)
      engagement_rows = Ahoy::Event
        .where(name: "engagement", time: range, visit_id: all_visit_ids)
        .pluck(Arel.sql("visit_id, time, COALESCE(NULLIF(split_part(ahoy_events.properties->>'page', '?', 1), ''), '(unknown)'), (ahoy_events.properties->>'engaged_ms'), (ahoy_events.properties->>'scroll_depth')"))

      engaged_pages_by_visit = Hash.new { |hash, key| hash[key] = Set.new }
      engagement_rows.each do |visit_id, _time, page, _engaged_ms, _scroll|
        engaged_pages_by_visit[visit_id] << (page.to_s.presence || "(unknown)")
      end

      by_visit.each do |visit_id, events|
        next if events.length <= 1

        (0...(events.length - 1)).each do |index|
          first_time, first_page = events[index]
          second_time, second_page = events[index + 1]
          label = first_page.to_s.presence || "(unknown)"
          next if first_page == second_page
          next if engaged_pages_by_visit[visit_id].include?(label)

          delta = [ (second_time - first_time).to_f, 0.0 ].max
          legacy_sum[label] += delta
          legacy_count[label] += 1
        end
      end

      new_sum = Hash.new(0.0)
      engagement_visits = Hash.new { |hash, key| hash[key] = Set.new }
      scroll_max_by_page_visit = Hash.new { |hash, key| hash[key] = {} }

      engagement_rows.each do |visit_id, _time, page, engaged_ms, scroll|
        label = page.to_s.presence || "(unknown)"
        seconds = begin
          value = engaged_ms.to_f
          value > 0 ? value / 1000.0 : 0.0
        rescue StandardError
          0.0
        end
        new_sum[label] += seconds
        engagement_visits[label] << visit_id

        scroll_depth = begin
          value = scroll.to_f
          value < 0 ? 0.0 : value
        rescue StandardError
          0.0
        end
        previous = scroll_max_by_page_visit[label][visit_id]
        scroll_max_by_page_visit[label][visit_id] = scroll_depth if previous.nil? || scroll_depth > previous
      end

      names.each_with_object({}) do |name, result|
        total_time = legacy_sum[name].to_f + new_sum[name].to_f
        denominator = legacy_count[name].to_i + engagement_visits[name]&.size.to_i
        time_on_page = denominator > 0 ? (total_time / denominator).round(1) : nil

        scroll_map = scroll_max_by_page_visit[name] || {}
        scroll_depth = if scroll_map.any?
          (scroll_map.values.sum.to_f / scroll_map.values.length.to_f).round
        end

        result[name] = { time_on_page: time_on_page, scroll_depth: scroll_depth }
      end
    end

    def goal_denominator_counts(query, mode:, search: nil)
      base_query = Analytics::Query.wrap(query)
        .without_goal_or_properties(property_filter: ->(key) { Analytics::Properties.filter_key?(key) })
        .with_option(:mode, mode)

      Analytics::PagesDatasetQuery.payload(query: base_query, search: search).fetch(:results, []).each_with_object({}) do |row, counts|
        counts[row[:name].to_s] = row[:visitors].to_i
      end
    end

    def filter_groups!(grouped_visit_ids, counts, comparison_names, *extra_maps)
      return if comparison_names.empty?

      matcher = ->(name) { comparison_names.include?(formatted_name(name)) }
      grouped_visit_ids.select! { |name, _| matcher.call(name) }
      counts.select! { |name, _| matcher.call(name) }
      extra_maps.compact.each do |metrics_map|
        metrics_map.select! { |name, _| matcher.call(name) }
      end
    end

    def formatted_name(name)
      name.to_s.presence || "(none)"
    end

    def internal_entry_label?(label)
      Analytics::InternalPaths.report_internal_path?(label)
    end

    def entry_page_label_by_visit(visits_relation, grouped_visit_ids)
      ids = grouped_visit_ids.values.flatten.uniq
      return {} if ids.empty?

      visits_relation.where(id: ids).pluck(:id, :landing_page).each_with_object({}) do |(visit_id, landing_page), result|
        result[visit_id] = Analytics::Urls.normalized_path_only(landing_page).presence || "(unknown)"
      end
    end

    def restrict_visits_to_entry_page(grouped_visit_ids, entry_page_label_by_visit)
      grouped_visit_ids.each_with_object({}) do |(name, ids), result|
        result[name] = ids.select { |visit_id| entry_page_label_by_visit[visit_id] == name }
      end
    end
  end
end
