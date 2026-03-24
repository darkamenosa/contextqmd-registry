module Ahoy::Visit::Filters
  extend ActiveSupport::Concern

  class_methods do
    # Build a case-insensitive SQL LIKE pattern that safely treats user input literally
    def like_contains(value)
      "%#{ActiveRecord::Base.sanitize_sql_like(value.to_s.downcase)}%"
    end

    def normalized_filter(filters, key)
      return unless filters
      value = filters[key]&.to_s
      return unless value
      value.strip.downcase.tr(" ", "-")
    end

    def filtered_visits(filters, advanced_filters: [])
      scope = Ahoy::Visit.all

      if filters.present?
        if (source = filters["source"]).present?
          s_down = source.to_s.downcase.strip
          if %w[direct / none (none) direct none directlink].include?(s_down)
            scope = scope.where(referring_domain: [ nil, "" ])
          elsif (pattern = domain_pattern_for_source_label(source))
            aliases = alias_sources_map.select { |_k, v| v.to_s.downcase == s_down }.keys
            if aliases.any?
              scope = scope.where(
                "referring_domain ~* ? OR LOWER(utm_source) IN (?) OR LOWER(utm_source) LIKE ?",
                pattern, aliases, "#{s_down}%"
              )
            else
              scope = scope.where(
                "referring_domain ~* ? OR LOWER(utm_source) = ? OR LOWER(utm_source) LIKE ?",
                pattern, s_down, "#{s_down}%"
              )
            end
          else
            if source.include?(".")
              scope = scope.where(referring_domain: source)
            else
              like = like_contains(source)
              scope = scope.where("LOWER(referring_domain) LIKE ? OR LOWER(utm_source) LIKE ?", like, like)
            end
          end
        elsif normalized_filter(filters, "source") == "direct"
          scope = scope.where(referring_domain: [ nil, "" ])
        end

        if (channel = filters["channel"]).present?
          val = Ahoy::Visit.connection.quote(channel)
          cond = "(#{Ahoy::Visit::Sources::CHANNEL_CASE_SQL}) = #{val}"
          scope = scope.where(Arel.sql(cond))
        end
        scope = scope.where(referrer: filters["referrer"]) if filters["referrer"].present?
        scope = scope.where(country: filters["country"]) if filters["country"].present?
        scope = scope.where(region:  filters["region"])  if filters["region"].present?
        scope = scope.where(city:    filters["city"])    if filters["city"].present?
        scope = scope.where(utm_source: filters["utm_source"]) if filters["utm_source"].present?
        scope = scope.where(utm_medium: filters["utm_medium"]) if filters["utm_medium"].present?
        scope = scope.where(utm_campaign: filters["utm_campaign"]) if filters["utm_campaign"].present?
        scope = scope.where(browser: filters["browser"]) if filters["browser"].present?
        scope = scope.where(os: filters["os"]) if filters["os"].present?
      end

      Array(advanced_filters).each do |op, dim, value|
        if dim == "channel"
          case op
          when "is_not"
            val = Ahoy::Visit.connection.quote(value)
            cond = "(#{Ahoy::Visit::Sources::CHANNEL_CASE_SQL}) <> #{val}"
            scope = scope.where(Arel.sql(cond))
          when "contains"
            pat = Ahoy::Visit.connection.quote(like_contains(value))
            cond = "LOWER((#{Ahoy::Visit::Sources::CHANNEL_CASE_SQL})) LIKE #{pat}"
            scope = scope.where(Arel.sql(cond))
          end
          next
        end
        if dim == "source"
          like = like_contains(value)
          case op
          when "contains"
            scope = scope.where("LOWER(referring_domain) LIKE ? OR LOWER(utm_source) LIKE ?", like, like)
          when "is_not"
            scope = scope.where("NOT (LOWER(referring_domain) LIKE ? OR LOWER(utm_source) LIKE ?)", like, like)
          end
          next
        end

        column = case dim
        when "referrer" then "referrer"
        when "utm_source", "utm_medium", "utm_campaign", "utm_content", "utm_term", "country", "region", "city", "browser", "os"
          dim
        else
          nil
        end
        next unless column

        if op == "is_not"
          scope = scope.where.not(Arel.sql(column) => value)
        elsif op == "contains"
          scope = scope.where("LOWER(#{column}) LIKE ?", like_contains(value))
        end
      end

      scope
    end

    def scoped_visits(range, filters, advanced_filters: [])
      basic_filters = filters.to_h.dup
      exit_page = basic_filters&.delete("exit_page")
      page_eq   = basic_filters&.delete("page")
      size_eq   = basic_filters&.delete("size")

      visits = filtered_visits(basic_filters, advanced_filters: advanced_filters).where(started_at: range)

      if (entry = filters["entry_page"]).present?
        decoded = begin
          CGI.unescape(entry.to_s)
        rescue StandardError
          entry.to_s
        end
        raw = normalized_path_and_query(decoded) || decoded
        label = raw.to_s.split("?").first.presence || "/"

        expr = "COALESCE(CASE WHEN strpos(regexp_replace(landing_page, '^(https://|http://)[^/]+', ''), chr(63)) > 0 THEN left(regexp_replace(landing_page, '^(https://|http://)[^/]+', ''), strpos(regexp_replace(landing_page, '^(https://|http://)[^/]+', ''), chr(63)) - 1) ELSE NULLIF(regexp_replace(landing_page, '^(https://|http://)[^/]+', ''), '') END, '/')"
        by_landing = visits.where(Arel.sql("#{expr} = ?"), label)

        candidate_ids = visits
          .where("landing_page IS NULL OR landing_page = '' OR regexp_replace(landing_page, '^(https://|http://)[^/]+', '') SIMILAR TO ?", "(/ahoy%|/cable%|/rails/%|/assets/%|/up%|/jobs%|/webhooks%)")
          .pluck(:id)

        derived_ids = []
        if candidate_ids.any?
          ev_rows = Ahoy::Event
            .where(name: "pageview", time: range, visit_id: candidate_ids)
            .pluck(Arel.sql("visit_id, time, COALESCE(ahoy_events.properties->>'page', '')"))
          first_page_by_visit = {}
          ev_rows.each do |vid, t, pg|
            prev = first_page_by_visit[vid]
            t_val = t.respond_to?(:to_time) ? t.to_time : t
            if prev.nil? || t_val < prev[0]
              first_page_by_visit[vid] = [ t_val, pg.to_s ]
            end
          end
          first_page_by_visit.each do |vid, (_t, pg)|
            next if pg.to_s.strip.empty?
            lp = normalized_path_only(pg)
            derived_ids << vid if lp.to_s == label
          end
        end

        visits = by_landing.or(visits.where(id: derived_ids.presence || [ 0 ]))
      end

      if exit_page.present?
        ids = visit_ids_with_exit_page(range, visits, exit_page)
        visits = visits.where(id: ids.presence || [ 0 ])
      end

      if page_eq.present?
        sub = Ahoy::Event
          .where(name: "pageview")
          .where(visit_id: visits.select(:id))
          .where(Arel.sql("ahoy_events.properties->>'page' = ?"), page_eq)
          .select(:visit_id)
          .distinct
        visits = visits.where(id: sub)
      end

      if size_eq.present?
        ids = visit_ids_for_screen_size_categories(visits, [ size_eq ])
        visits = visits.where(id: ids.presence || [ 0 ])
      end

      Array(advanced_filters).each do |op, dim, value|
        next unless dim == "page"
        next if value.to_s.strip.empty?
        case op
        when "contains"
          sub = Ahoy::Event
            .where(name: "pageview")
            .where(visit_id: visits.select(:id))
            .where("LOWER(ahoy_events.properties->>'page') LIKE ?", like_contains(value))
            .select(:visit_id).distinct
          visits = visits.where(id: sub)
        when "is_not"
          sub = Ahoy::Event
            .where(name: "pageview")
            .where(visit_id: visits.select(:id))
            .where(Arel.sql("ahoy_events.properties->>'page' = ?"), value)
            .select(:visit_id).distinct
          visits = visits.where.not(id: sub)
        end
      end

      Array(advanced_filters).each do |op, dim, value|
        next unless dim == "size"
        needle = value.to_s.strip.downcase
        next if needle.empty?

        case op
        when "contains"
          categories = %w[Mobile Tablet Laptop Desktop (not\ set)].select { |c| c.downcase.include?(needle) }
          ids = visit_ids_for_screen_size_categories(visits, categories)
          visits = visits.where(id: ids.presence || [ 0 ])
        when "is_not"
          ids = visit_ids_for_screen_size_categories(visits, [ value.to_s ])
          visits = visits.where.not(id: ids.presence || [ 0 ])
        end
      end

      visits
    end

    def scoped_events(range, filters, advanced_filters: [])
      basic_filters = filters.to_h.dup
      exit_page = basic_filters&.delete("exit_page")

      scope = Ahoy::Event
        .where(name: "pageview", time: range)
        .joins(:visit)
        .merge(filtered_visits(basic_filters, advanced_filters: advanced_filters))

      if exit_page.present?
        visit_scope = Ahoy::Visit.where(id: scope.select(:visit_id).distinct)
        ids = visit_ids_with_exit_page(range, visit_scope, exit_page)
        scope = scope.where(visit_id: ids.presence || [ 0 ])
      end

      if filters["page"].present?
        scope = scope.where(Arel.sql("ahoy_events.properties->>'page' = ?"), filters["page"])
      end

      Array(advanced_filters).each do |op, dim, value|
        next unless dim == "page"
        if op == "is_not"
          scope = scope.where.not(Arel.sql("ahoy_events.properties->>'page' = ?"), value)
        elsif op == "contains"
          scope = scope.where("LOWER(ahoy_events.properties->>'page') LIKE ?", like_contains(value))
        end
      end

      scope
    end

    def visit_ids_with_exit_page(range, visits_scope, exit_page)
      return [] if visits_scope.none?

      expr = "COALESCE(NULLIF(split_part(ahoy_events.properties->>'page', '?', 1), ''), '')"
      rows = Ahoy::Event
        .where(name: "pageview", time: range)
        .where(visit_id: visits_scope.select(:id))
        .pluck(Arel.sql("visit_id, time, #{expr}"))

      last_page_by_visit = {}
      rows.each do |vid, t, page_name|
        prev = last_page_by_visit[vid]
        t_val = t.respond_to?(:to_time) ? t.to_time : t
        prev_time = prev ? (prev.is_a?(Array) ? prev[0] : prev.first) : nil
        if prev.nil? || t_val > prev_time
          last_page_by_visit[vid] = [ t_val, page_name.to_s ]
        end
      end

      needle = exit_page.to_s.split("?").first
      last_page_by_visit.filter_map { |vid, (_t, page)| vid if page == needle }
    end

    def visit_ids_for_screen_size_categories(visits_scope, categories)
      return [] if visits_scope.none?

      raw = visits_scope.group(:screen_size).pluck(:screen_size, Arel.sql("ARRAY_AGG(id)"))
      categories_down = categories.map(&:to_s)
      selected = []
      raw.each do |screen_size, visit_ids|
        cat = categorize_screen_size(screen_size)
        if categories_down.any? { |c| c.to_s == cat.to_s }
          selected.concat(Array(visit_ids))
        end
      end
      selected
    end
  end
end
