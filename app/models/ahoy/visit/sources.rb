module Ahoy::Visit::Sources
  extend ActiveSupport::Concern

  class_methods do
    def legacy_source_label_expr
      <<~SQL.squish
        COALESCE(
          NULLIF(utm_source, ''),
          NULLIF(referring_domain, ''),
          '#{Analytics::SourceResolver::DIRECT_LABEL}'
        )
      SQL
    end

    def source_label_expr
      "COALESCE(NULLIF(source_label, ''), #{legacy_source_label_expr})"
    end

    def source_label_sql_node
      sql_expression_node(source_label_expr)
    end

    def source_channel_expr
      <<~SQL.squish
        COALESCE(
          NULLIF(source_channel, ''),
          CASE
            WHEN NULLIF(utm_medium, '') IS NOT NULL THEN #{utm_medium_expr}
            WHEN NULLIF(referring_domain, '') IS NOT NULL THEN 'Referral'
            ELSE 'Direct'
          END
        )
      SQL
    end

    def source_channel_sql_node
      sql_expression_node(source_channel_expr)
    end

    def utm_medium_expr
      <<~SQL
        COALESCE(
          NULLIF(utm_medium, ''),
          CASE
            WHEN landing_page ILIKE '%gclid=%' THEN '(gclid)'
            WHEN landing_page ILIKE '%msclkid=%' THEN '(msclkid)'
            ELSE '(not set)'
          END
        )
      SQL
    end

    def normalize_source_label(value)
      Analytics::SourceResolver.resolve(referring_domain: value).source_label
    end

    def normalize_source_name(value)
      candidate = value.to_s.strip
      return Analytics::SourceResolver::DIRECT_LABEL if candidate.blank?

      Analytics::SourceResolver.canonical_label(candidate) ||
        Analytics::SourceResolver.resolve(referring_domain: candidate).source_label
    end

    def source_match_values(value)
      candidate = value.to_s.strip
      return [ Analytics::SourceResolver::DIRECT_LABEL ] if candidate.blank?

      [ candidate, normalize_source_name(candidate) ].compact_blank.uniq
    end

    def filter_scope_for_source(scope, source)
      values = source_match_values(source)
      scope.where(source_label_sql_node.in(values))
    end

    def sources_payload(query, limit: nil, page: nil, search: nil, order_by: nil)
      mode = query[:mode] || "all"
      filters = query[:filters] || {}
      comparison_names = Ahoy::Visit.comparison_names_filter(query)
      range, = Ahoy::Visit.range_and_interval_for(query[:period], nil, query)
      visits = Ahoy::Visit.scoped_visits(range, filters, advanced_filters: query[:advanced_filters] || [])
      goal = filters["goal"].presence

      expr, where_clause = source_mode_sql(mode)

      if limit && page
        rel = visits
        if search.present? && where_clause.present?
          rel = rel.where([ where_clause, Ahoy::Visit.like_contains(search) ])
        end

        grouped_visit_ids = rel.group(Arel.sql(expr)).pluck(Arel.sql("#{expr}, ARRAY_AGG(ahoy_visits.id)")).to_h
        counts = Ahoy::Visit.unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits)

        if mode.start_with?("utm-")
          grouped_visit_ids.delete(nil)
          grouped_visit_ids.delete("")
          grouped_visit_ids.delete("(not set)")
          counts.delete(nil)
          counts.delete("")
          counts.delete("(not set)")
        end

        filter_source_groups!(mode, grouped_visit_ids, counts, comparison_names)
        total = Ahoy::Visit.percentage_total_visitors(visits)

        sorted_names = if goal.present?
          denominator_counts = goal_denominator_counts_for_sources(query, mode: mode, search: search)
          conversions_all, cr_all = Ahoy::Visit.conversions_and_rates(
            grouped_visit_ids,
            visits,
            range,
            filters,
            goal,
            advanced_filters: query[:advanced_filters] || [],
            denominator_counts: denominator_counts
          )
          Ahoy::Visit.order_names_with_conversions(conversions: conversions_all, cr: cr_all, order_by: order_by)
        elsif order_by
          order_metrics = source_order_metrics(order_by, grouped_visit_ids, counts, range, filters, total)
          Ahoy::Visit.order_names(counts: counts, metrics_map: order_metrics, order_by: order_by)
        else
          Ahoy::Visit.order_names(counts: counts, metrics_map: {}, order_by: nil)
        end

        paged_names, has_more = Ahoy::Visit.paginate_names(sorted_names, limit: limit, page: page)
        page_visit_ids = grouped_visit_ids.slice(*paged_names)
        source_previews = mode == "all" ? source_debug_previews(page_visit_ids) : {}

        if goal.present?
          denominator_counts = goal_denominator_counts_for_sources(query, mode: mode, search: search)
          conversions, = Ahoy::Visit.conversions_and_rates(
            page_visit_ids,
            visits,
            range,
            filters,
            goal,
            advanced_filters: query[:advanced_filters] || [],
            denominator_counts: denominator_counts
          )

          results = paged_names.map do |name|
            label = formatted_source_name(mode, name)
            row = {
              name: label,
              visitors: conversions[name] || 0,
              conversion_rate: Ahoy::Visit.goal_conversion_rate(conversions[name] || 0, denominator_counts[label])
            }
            row[:source_info] = source_previews[name] if source_previews[name]
            row
          end

          {
            results: results,
            metrics: %i[visitors conversion_rate],
            meta: {
              has_more: has_more,
              skip_imported_reason: Ahoy::Visit.skip_imported_reason(query),
              metric_labels: { visitors: "Conversions", conversionRate: "Conversion Rate" }
            }
          }
        else
          metrics = Ahoy::Visit.calculate_group_metrics(page_visit_ids, range, filters)
          results = paged_names.map do |name|
            row = {
              name: formatted_source_name(mode, name),
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
              skip_imported_reason: Ahoy::Visit.skip_imported_reason(query),
              metric_labels: { percentage: "Percentage" }
            }
          }
        end
      else
        counts = visits.group(Arel.sql(expr)).count("DISTINCT visitor_token")
        counts.delete(nil) if mode.start_with?("utm-")
        counts.delete("") if mode.start_with?("utm-")
        counts.delete("(not set)") if mode.start_with?("utm-")

        total = Ahoy::Visit.percentage_total_visitors(visits)
        rows = counts.sort_by { |_, value| -value }.map do |name, value|
          {
            name: formatted_source_name(mode, name),
            visitors: value,
            percentage: (value.to_f / total).round(3)
          }
        end

        {
          results: rows,
          metrics: %i[visitors percentage],
          meta: {
            has_more: false,
            skip_imported_reason: Ahoy::Visit.skip_imported_reason(query),
            metric_labels: { percentage: "Percentage" }
          }
        }
      end
    end

    def referrers_payload(query, source, limit: nil, page: nil, search: nil, order_by: nil)
      range, = Ahoy::Visit.range_and_interval_for(query[:period], nil, query)
      filters = query[:filters] || {}
      advanced_filters = query[:advanced_filters] || []
      comparison_names = Ahoy::Visit.comparison_names_filter(query)
      goal = filters["goal"].presence

      normalized_source = normalize_source_name(source)
      base_visits = Ahoy::Visit.scoped_visits(range, filters, advanced_filters: advanced_filters)
      visits = filter_scope_for_source(base_visits, source)

      if normalized_source == Analytics::SourceResolver::DIRECT_LABEL
        counts = { Analytics::SourceResolver::DIRECT_LABEL => visits.distinct.count(:visitor_token) }
        counts = {} if comparison_names.any? && !comparison_names.include?(Analytics::SourceResolver::DIRECT_LABEL)

        if limit && page
          grouped_visit_ids = counts.empty? ? {} : { Analytics::SourceResolver::DIRECT_LABEL => visits.pluck(:id) }
          if goal.present?
            denominator_counts = goal_denominator_counts_for_referrers(query, normalized_source, search: search)
            conversions, = Ahoy::Visit.conversions_and_rates(
              grouped_visit_ids,
              visits,
              range,
              filters,
              goal,
              advanced_filters: advanced_filters,
              denominator_counts: denominator_counts
            )
            rows = counts.map do |name, _|
              {
                name: name,
                visitors: conversions[name] || 0,
                conversion_rate: Ahoy::Visit.goal_conversion_rate(conversions[name] || 0, denominator_counts[name])
              }
            end

            {
              results: rows,
              metrics: %i[visitors conversion_rate],
              meta: {
                has_more: false,
                skip_imported_reason: Ahoy::Visit.skip_imported_reason(query),
                metric_labels: { visitors: "Conversions", conversionRate: "Conversion Rate" }
              }
            }
          else
            metrics = Ahoy::Visit.calculate_group_metrics(grouped_visit_ids, range, filters)
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
              meta: { has_more: false, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query) }
            }
          end
        else
          rows = counts.sort_by { |_, value| -value }.map { |name, value| { name: name, visitors: value } }
          { results: rows, metrics: %i[visitors], meta: { has_more: false, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query) } }
        end
      else
        expr = "COALESCE(referrer, '#{Analytics::SourceResolver::DIRECT_LABEL}')"
        rel = visits
        rel = rel.where("LOWER(referrer) LIKE ?", Ahoy::Visit.like_contains(search)) if search.present?

        if limit && page
          grouped_visit_ids = rel.group(Arel.sql(expr)).pluck(Arel.sql("#{expr}, ARRAY_AGG(ahoy_visits.id)")).to_h
          counts = Ahoy::Visit.unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits)

          if comparison_names.any?
            grouped_visit_ids.select! { |name, _| comparison_names.include?(name.to_s) }
            counts.select! { |name, _| comparison_names.include?(name.to_s) }
          end

          sorted_names = if goal.present?
            denominator_counts = goal_denominator_counts_for_referrers(query, normalized_source, search: search)
            conversions_all, cr_all = Ahoy::Visit.conversions_and_rates(
              grouped_visit_ids,
              visits,
              range,
              filters,
              goal,
              advanced_filters: advanced_filters,
              denominator_counts: denominator_counts
            )
            Ahoy::Visit.order_names_with_conversions(conversions: conversions_all, cr: cr_all, order_by: order_by)
          elsif order_by && %w[bounce_rate visit_duration].include?(order_by[0])
            metrics = Ahoy::Visit.calculate_group_metrics(grouped_visit_ids, range, filters)
            Ahoy::Visit.order_names(counts: counts, metrics_map: counts.keys.index_with { |name| metrics[name] || {} }, order_by: order_by)
          else
            Ahoy::Visit.order_names(counts: counts, metrics_map: {}, order_by: order_by)
          end

          paged_names, has_more = Ahoy::Visit.paginate_names(sorted_names, limit: limit, page: page)
          page_visit_ids = grouped_visit_ids.slice(*paged_names)

          if goal.present?
            denominator_counts = goal_denominator_counts_for_referrers(query, normalized_source, search: search)
            conversions, = Ahoy::Visit.conversions_and_rates(
              page_visit_ids,
              visits,
              range,
              filters,
              goal,
              advanced_filters: advanced_filters,
              denominator_counts: denominator_counts
            )
            results = paged_names.map do |name|
              {
                name: name,
                visitors: conversions[name] || 0,
                conversion_rate: Ahoy::Visit.goal_conversion_rate(conversions[name] || 0, denominator_counts[name])
              }
            end
            {
              results: results,
              metrics: %i[visitors conversion_rate],
              meta: {
                has_more: has_more,
                skip_imported_reason: Ahoy::Visit.skip_imported_reason(query),
                metric_labels: { visitors: "Conversions", conversionRate: "Conversion Rate" }
              }
            }
          else
            metrics = Ahoy::Visit.calculate_group_metrics(page_visit_ids, range, filters)
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
              meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query) }
            }
          end
        else
          counts = rel.group(Arel.sql(expr)).distinct.count(:visitor_token)
          rows = counts.sort_by { |_, value| -value }.map { |name, value| { name: name.to_s.presence || "(none)", visitors: value } }
          { results: rows, metrics: %i[visitors], meta: { has_more: false, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query) } }
        end
      end
    end

    def goal_denominator_counts_for_sources(query, mode:, search: nil)
      base_query = Ahoy::Visit.query_without_goal_and_props(query).merge(mode: mode)
      payload = sources_payload(base_query, search: search)
      payload.fetch(:results, []).each_with_object({}) do |row, counts|
        counts[row[:name].to_s] = row[:visitors].to_i
      end
    end

    def goal_denominator_counts_for_referrers(query, source, search: nil)
      base_query = Ahoy::Visit.query_without_goal_and_props(query)
      payload = referrers_payload(base_query, source, search: search)
      payload.fetch(:results, []).each_with_object({}) do |row, counts|
        counts[row[:name].to_s] = row[:visitors].to_i
      end
    end

    def filter_source_groups!(mode, grouped_visit_ids, counts, comparison_names)
      return if comparison_names.empty?

      grouped_visit_ids.select! { |name, _| comparison_names.include?(formatted_source_name(mode, name)) }
      counts.select! { |name, _| comparison_names.include?(formatted_source_name(mode, name)) }
    end

    def formatted_source_name(mode, name)
      label = name.to_s
      return mode.start_with?("utm-") ? "(not set)" : "(none)" if label.strip.empty?

      label
    end

    def source_debug_payload(query, source)
      range, = Ahoy::Visit.range_and_interval_for(query[:period], nil, query)
      filters = query[:filters] || {}
      advanced_filters = query[:advanced_filters] || []
      normalized_source = normalize_source_name(source)
      visits = Ahoy::Visit
        .scoped_visits(range, filters, advanced_filters: advanced_filters)
        .yield_self { |scope| filter_scope_for_source(scope, source) }

      {
        source: {
          requested_value: source.to_s,
          normalized_value: normalized_source,
          kind: Analytics::SourceResolver.kind_for(normalized_source),
          favicon_domain: Analytics::SourceResolver.favicon_domain_for(normalized_source),
          visitors: visits.distinct.count(:visitor_token),
          visits: visits.count,
          fallback_count: visits.where("source_match_strategy LIKE ?", "fallback%").count
        },
        channels: sorted_count_rows(visits.group(Arel.sql(source_channel_expr)).count("DISTINCT visitor_token")),
        matched_rules: sorted_count_rows(visits.group(:source_rule_id).count),
        match_strategies: sorted_count_rows(visits.group(:source_match_strategy).count),
        raw_referring_domains: sorted_count_rows(visits.where.not(referring_domain: [ nil, "" ]).group(:referring_domain).count),
        raw_utm_sources: sorted_count_rows(visits.where.not(utm_source: [ nil, "" ]).group(:utm_source).count),
        raw_referrers: sorted_count_rows(visits.where.not(referrer: [ nil, "" ]).group(:referrer).count),
        latest_samples: visits
          .order(started_at: :desc)
          .limit(10)
          .pluck(
            :started_at,
            :referring_domain,
            :utm_source,
            :utm_medium,
            :referrer,
            :source_rule_id,
            :source_match_strategy
          )
          .map do |started_at, referring_domain, utm_source, utm_medium, referrer, source_rule_id, source_match_strategy|
            {
              started_at: started_at&.iso8601,
              referring_domain: referring_domain,
              utm_source: utm_source,
              utm_medium: utm_medium,
              referrer: referrer,
              rule_id: source_rule_id,
              match_strategy: source_match_strategy
            }
          end
      }
    end

    private
      def source_debug_previews(grouped_visit_ids)
        ids_to_source = {}
        grouped_visit_ids.each do |name, ids|
          ids.each { |visit_id| ids_to_source[visit_id] = formatted_source_name("all", name) }
        end
        return {} if ids_to_source.empty?

        previews = Hash.new do |hash, key|
          hash[key] = {
            raw_referring_domains: Hash.new(0),
            raw_utm_sources: Hash.new(0),
            matched_rules: Hash.new(0),
            match_strategies: Hash.new(0)
          }
        end

        Ahoy::Visit.where(id: ids_to_source.keys).pluck(:id, :referring_domain, :utm_source, :source_rule_id, :source_match_strategy).each do |visit_id, referring_domain, utm_source, source_rule_id, source_match_strategy|
          source_name = ids_to_source[visit_id]
          next if source_name.blank?

          previews[source_name][:raw_referring_domains][referring_domain] += 1 if referring_domain.present?
          previews[source_name][:raw_utm_sources][utm_source] += 1 if utm_source.present?
          previews[source_name][:matched_rules][source_rule_id] += 1 if source_rule_id.present?
          previews[source_name][:match_strategies][source_match_strategy] += 1 if source_match_strategy.present?
        end

        previews.transform_values do |stats|
          {
            filter_value: nil,
            normalized_name: nil,
            top_referring_domain: sorted_count_rows(stats[:raw_referring_domains], limit: 1).first&.fetch(:value, nil),
            top_utm_source: sorted_count_rows(stats[:raw_utm_sources], limit: 1).first&.fetch(:value, nil),
            top_rule_id: sorted_count_rows(stats[:matched_rules], limit: 1).first&.fetch(:value, nil),
            top_match_strategy: sorted_count_rows(stats[:match_strategies], limit: 1).first&.fetch(:value, nil),
            raw_referring_domains: sorted_count_rows(stats[:raw_referring_domains], limit: 3),
            raw_utm_sources: sorted_count_rows(stats[:raw_utm_sources], limit: 3),
            matched_rules: sorted_count_rows(stats[:matched_rules], limit: 3),
            match_strategies: sorted_count_rows(stats[:match_strategies], limit: 3)
          }
        end.tap do |result|
          result.each do |name, info|
            info[:filter_value] = name
            info[:normalized_name] = name
          end
        end
      end

      def sorted_count_rows(counts, limit: 10)
        counts
          .reject { |value, count| value.to_s.strip.empty? || count.to_i <= 0 }
          .sort_by { |value, count| [ -count.to_i, value.to_s ] }
          .first(limit)
          .map { |value, count| { value: value.to_s, count: count.to_i } }
      end

      def sql_expression_node(expression)
        Arel::Nodes::Grouping.new(Arel.sql(expression))
      end

      def source_mode_sql(mode)
        case mode
        when "channels"
          [ source_channel_expr, "LOWER(#{source_channel_expr}) LIKE ?" ]
        when "referrers"
          [ "COALESCE(referring_domain, '#{Analytics::SourceResolver::DIRECT_LABEL}')", "LOWER(COALESCE(referring_domain, '#{Analytics::SourceResolver::DIRECT_LABEL}')) LIKE ?" ]
        when "all"
          [ source_label_expr, "LOWER(#{source_label_expr}) LIKE ?" ]
        when "utm-medium"
          [ utm_medium_expr, "LOWER(#{utm_medium_expr}) LIKE ?" ]
        when "utm-source"
          [ "utm_source", "LOWER(utm_source) LIKE ?" ]
        when "utm-campaign"
          [ "utm_campaign", "LOWER(utm_campaign) LIKE ?" ]
        when "utm-content"
          [ "utm_content", "LOWER(utm_content) LIKE ?" ]
        when "utm-term", "search-terms"
          [ "utm_term", "LOWER(utm_term) LIKE ?" ]
        else
          [ source_label_expr, "LOWER(#{source_label_expr}) LIKE ?" ]
        end
      end

      def source_order_metrics(order_by, grouped_visit_ids, counts, range, filters, total)
        case order_by[0]
        when "percentage"
          counts.keys.index_with { |name| { percentage: (counts[name].to_f / total) } }
        when "bounce_rate", "visit_duration"
          metrics = Ahoy::Visit.calculate_group_metrics(grouped_visit_ids, range, filters)
          counts.keys.index_with { |name| metrics[name] || {} }
        else
          {}
        end
      end
  end
end
