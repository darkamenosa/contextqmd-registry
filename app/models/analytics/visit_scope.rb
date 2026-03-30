# frozen_string_literal: true

class Analytics::VisitScope
  class << self
    def filtered(query_or_filters = nil, advanced_filters: [])
      query = normalize_query(query_or_filters, advanced_filters:)
      filters = query.filters
      advanced_filters = query.advanced_filters
      scope = Ahoy::Visit.for_analytics_site

      if filters.present?
        if (source = filters["source"]).present?
          scope = scope.where(Analytics::Sources.source_label_sql_node.in(Analytics::Sources.match_values(source)))
        elsif normalized_filter(filters, "source") == "direct"
          scope = scope.where(Analytics::Sources.source_label_sql_node.eq(Analytics::SourceResolver::DIRECT_LABEL))
        end

        if (channel = filters["channel"]).present?
          scope = scope.where(Analytics::Sources.source_channel_sql_node.eq(channel))
        end
        scope = scope.where(referrer: filters["referrer"]) if filters["referrer"].present?
        if (country_filter = filters["country"]).present?
          normalized_country_code = Ahoy::Visit.normalize_country_code(country_filter)
          scope = normalized_country_code.present? ? scope.where(country_code: normalized_country_code) : scope.none
        end
        scope = scope.where(region: filters["region"]) if filters["region"].present?
        scope = scope.where(city: filters["city"]) if filters["city"].present?
        scope = scope.where(utm_source: filters["utm_source"]) if filters["utm_source"].present?
        scope = scope.where(utm_medium: filters["utm_medium"]) if filters["utm_medium"].present?
        scope = scope.where(utm_campaign: filters["utm_campaign"]) if filters["utm_campaign"].present?
        scope = scope.where(browser: filters["browser"]) if filters["browser"].present?
        scope = scope.where(browser_version: filters["browser_version"]) if filters["browser_version"].present?
        scope = scope.where(os: filters["os"]) if filters["os"].present?
        scope = scope.where(os_version: filters["os_version"]) if filters["os_version"].present?

        filters.each do |key, value|
          next unless Analytics::Properties.filter_key?(key)
          next if value.blank?

          scope = apply_property_filter(scope, key, "is", value)
        end
      end

      Array(advanced_filters).each do |operator, dimension, value|
        if Analytics::Properties.filter_key?(dimension)
          scope = apply_property_filter(scope, dimension, operator, value)
          next
        end

        if dimension == "channel"
          case operator
          when "is_not"
            scope = scope.where(Analytics::Sources.source_channel_sql_node.not_eq(value))
          when "contains"
            scope = scope.where(
              Arel::Nodes::NamedFunction.new("LOWER", [ Analytics::Sources.source_channel_sql_node ])
                .matches(Analytics::Search.contains_pattern(value), nil, true)
            )
          end
          next
        end

        if dimension == "source"
          case operator
          when "contains"
            scope = scope.where(
              Arel::Nodes::NamedFunction.new("LOWER", [ Analytics::Sources.source_label_sql_node ])
                .matches(Analytics::Search.contains_pattern(value), nil, true)
            )
          when "is_not"
            scope = scope.where(
              Arel::Nodes::NamedFunction.new("LOWER", [ Analytics::Sources.source_label_sql_node ])
                .does_not_match(Analytics::Search.contains_pattern(value), nil, true)
            )
          end
          next
        end

        if dimension == "country"
          if operator == "is_not"
            normalized_country_code = Ahoy::Visit.normalize_country_code(value)
            scope = normalized_country_code.present? ? scope.where.not(country_code: normalized_country_code) : scope
          elsif operator == "contains"
            matching_codes = Ahoy::Visit.matching_country_codes(value)
            scope = matching_codes.any? ? scope.where(country_code: matching_codes) : scope.none
          end
          next
        end

        column = case dimension
        when "referrer" then "referrer"
        when "utm_source", "utm_medium", "utm_campaign", "utm_content", "utm_term", "region", "city", "browser", "browser_version", "os", "os_version"
          dimension
        end
        next unless column

        if operator == "is_not"
          scope = scope.where.not(Arel.sql(column) => value)
        elsif operator == "contains"
          scope = scope.where("LOWER(#{column}) LIKE ?", Analytics::Search.contains_pattern(value))
        end
      end

      scope
    end

    def visits(range, query_or_filters = nil, advanced_filters: [])
      query = normalize_query(query_or_filters, advanced_filters:)
      filters = query.filters
      advanced_filters = query.advanced_filters
      basic_filters = filters.to_h.dup
      exit_page = basic_filters.delete("exit_page")
      page_eq = basic_filters.delete("page")
      size_eq = basic_filters.delete("size")

      visits = filtered(basic_filters, advanced_filters: advanced_filters).where(started_at: range)

      if (entry = filters["entry_page"]).present?
        decoded = begin
          CGI.unescape(entry.to_s)
        rescue StandardError
          entry.to_s
        end
        raw = Analytics::Urls.normalized_path_and_query(decoded) || decoded
        label = raw.to_s.split("?").first.presence || "/"

        expr = "COALESCE(CASE WHEN strpos(regexp_replace(landing_page, '^(https://|http://)[^/]+', ''), chr(63)) > 0 THEN left(regexp_replace(landing_page, '^(https://|http://)[^/]+', ''), strpos(regexp_replace(landing_page, '^(https://|http://)[^/]+', ''), chr(63)) - 1) ELSE NULLIF(regexp_replace(landing_page, '^(https://|http://)[^/]+', ''), '') END, '/')"
        by_landing = visits.where(Arel.sql("#{expr} = ?"), label)

        candidate_ids = visits
          .where("landing_page IS NULL OR landing_page = '' OR regexp_replace(landing_page, '^(https://|http://)[^/]+', '') SIMILAR TO ?", "(/ahoy%|/cable%|/rails/%|/assets/%|/up%|/jobs%|/webhooks%)")
          .pluck(:id)

        derived_ids = []
        if candidate_ids.any?
          event_rows = Ahoy::Event
            .where(name: "pageview", time: range, visit_id: candidate_ids)
            .pluck(Arel.sql("visit_id, time, COALESCE(ahoy_events.properties->>'page', '')"))
          first_page_by_visit = {}
          event_rows.each do |visit_id, time, page|
            previous = first_page_by_visit[visit_id]
            time_value = time.respond_to?(:to_time) ? time.to_time : time
            if previous.nil? || time_value < previous[0]
              first_page_by_visit[visit_id] = [ time_value, page.to_s ]
            end
          end
          first_page_by_visit.each do |visit_id, (_time, page)|
            next if page.to_s.strip.empty?

            landing_page = Analytics::Urls.normalized_path_only(page)
            derived_ids << visit_id if landing_page.to_s == label
          end
        end

        visits = by_landing.or(visits.where(id: derived_ids.presence || [ 0 ]))
      end

      if exit_page.present?
        ids = visit_ids_with_exit_page(range, visits, exit_page)
        visits = visits.where(id: ids.presence || [ 0 ])
      end

      if page_eq.present?
        matching_pageviews = Ahoy::Event
          .where(name: "pageview")
          .where(visit_id: visits.select(:id))
          .where(Arel.sql("ahoy_events.properties->>'page' = ?"), page_eq)
          .select(:visit_id)
          .distinct
        visits = visits.where(id: matching_pageviews)
      end

      if size_eq.present?
        ids = visit_ids_for_screen_size_categories(visits, [ size_eq ])
        visits = visits.where(id: ids.presence || [ 0 ])
      end

      Array(advanced_filters).each do |operator, dimension, value|
        next unless dimension == "page"
        next if value.to_s.strip.empty?

        case operator
        when "contains"
          matching_pageviews = Ahoy::Event
            .where(name: "pageview")
            .where(visit_id: visits.select(:id))
            .where("LOWER(ahoy_events.properties->>'page') LIKE ?", Analytics::Search.contains_pattern(value))
            .select(:visit_id)
            .distinct
          visits = visits.where(id: matching_pageviews)
        when "is_not"
          matching_pageviews = Ahoy::Event
            .where(name: "pageview")
            .where(visit_id: visits.select(:id))
            .where(Arel.sql("ahoy_events.properties->>'page' = ?"), value)
            .select(:visit_id)
            .distinct
          visits = visits.where.not(id: matching_pageviews)
        end
      end

      Array(advanced_filters).each do |operator, dimension, value|
        next unless dimension == "size"

        needle = value.to_s.strip.downcase
        next if needle.empty?

        case operator
        when "contains"
          categories = %w[Mobile Tablet Laptop Desktop (not\ set)].select { |category| category.downcase.include?(needle) }
          ids = visit_ids_for_screen_size_categories(visits, categories)
          visits = visits.where(id: ids.presence || [ 0 ])
        when "is_not"
          ids = visit_ids_for_screen_size_categories(visits, [ value.to_s ])
          visits = visits.where.not(id: ids.presence || [ 0 ])
        end
      end

      visits
    end

    def pageviews(range, query_or_filters = nil, advanced_filters: [])
      query = normalize_query(query_or_filters, advanced_filters:)
      filters = query.filters
      advanced_filters = query.advanced_filters
      basic_filters = filters.to_h.dup
      exit_page = basic_filters.delete("exit_page")

      pageviews = Ahoy::Event
        .for_analytics_site
        .where(name: "pageview", time: range)
        .joins(:visit)
        .merge(filtered(basic_filters, advanced_filters: advanced_filters))

      if exit_page.present?
        visit_scope = Ahoy::Visit.where(id: pageviews.select(:visit_id).distinct)
        ids = visit_ids_with_exit_page(range, visit_scope, exit_page)
        pageviews = pageviews.where(visit_id: ids.presence || [ 0 ])
      end

      if filters["page"].present?
        pageviews = pageviews.where(Arel.sql("ahoy_events.properties->>'page' = ?"), filters["page"])
      end

      Array(advanced_filters).each do |operator, dimension, value|
        next unless dimension == "page"

        if operator == "is_not"
          pageviews = pageviews.where.not(Arel.sql("ahoy_events.properties->>'page' = ?"), value)
        elsif operator == "contains"
          pageviews = pageviews.where("LOWER(ahoy_events.properties->>'page') LIKE ?", Analytics::Search.contains_pattern(value))
        end
      end

      pageviews
    end

    def apply_property_filter(scope, filter_key, operator, value)
      property = Analytics::Properties.filter_name(filter_key)
      return scope if property.blank? || value.to_s.strip.empty?

      quoted_property = Ahoy::Visit.connection.quote(property)
      value_expr = "COALESCE(NULLIF(ahoy_events.properties->>#{quoted_property}, ''), '(none)')"
      matched_visits = Ahoy::Event
        .where(visit_id: scope.select(:id))
        .where(Arel.sql("ahoy_events.properties ? #{quoted_property}"))

      case operator
      when "contains"
        matched_visits = matched_visits.where("LOWER(#{value_expr}) LIKE ?", Analytics::Search.contains_pattern(value))
        scope.where(id: matched_visits.select(:visit_id).distinct)
      when "is_not"
        matched_visits = matched_visits.where(Arel.sql("#{value_expr} = ?"), value.to_s)
        scope.where.not(id: matched_visits.select(:visit_id).distinct)
      else
        matched_visits = matched_visits.where(Arel.sql("#{value_expr} = ?"), value.to_s)
        scope.where(id: matched_visits.select(:visit_id).distinct)
      end
    end

    def normalized_filter(filters, key)
      return unless filters

      value = filters[key]&.to_s
      return unless value

      value.strip.downcase.tr(" ", "-")
    end

    def normalize_query(query_or_filters, advanced_filters: [])
      if query_or_filters.is_a?(Analytics::Query)
        query_or_filters
      else
        Analytics::Query.new(filters: query_or_filters, advanced_filters: advanced_filters)
      end
    end

    private
      def visit_ids_with_exit_page(range, visits_scope, exit_page)
        return [] if visits_scope.none?

        expr = "COALESCE(NULLIF(split_part(ahoy_events.properties->>'page', '?', 1), ''), '')"
        rows = Ahoy::Event
          .where(name: "pageview", time: range)
          .where(visit_id: visits_scope.select(:id))
          .pluck(Arel.sql("visit_id, time, #{expr}"))

        last_page_by_visit = {}
        rows.each do |visit_id, time, page_name|
          previous = last_page_by_visit[visit_id]
          time_value = time.respond_to?(:to_time) ? time.to_time : time
          previous_time = previous ? (previous.is_a?(Array) ? previous[0] : previous.first) : nil
          if previous.nil? || time_value > previous_time
            last_page_by_visit[visit_id] = [ time_value, page_name.to_s ]
          end
        end

        needle = exit_page.to_s.split("?").first
        last_page_by_visit.filter_map { |visit_id, (_time, page)| visit_id if page == needle }
      end

      def visit_ids_for_screen_size_categories(visits_scope, categories)
        return [] if visits_scope.none?

        raw = visits_scope.group(:screen_size).pluck(:screen_size, Arel.sql("ARRAY_AGG(id)"))
        category_names = categories.map(&:to_s)
        selected = []

        raw.each do |screen_size, visit_ids|
          category = Analytics::Devices.categorize_screen_size(screen_size)
          if category_names.any? { |name| name.to_s == category.to_s }
            selected.concat(Array(visit_ids))
          end
        end

        selected
      end
  end
end
