# frozen_string_literal: true

module Analytics::Sources
  class << self
    def legacy_source_label_expression
      <<~SQL.squish
        COALESCE(
          NULLIF(utm_source, ''),
          NULLIF(referring_domain, ''),
          '#{Analytics::SourceResolver::DIRECT_LABEL}'
        )
      SQL
    end

    def source_label_expression
      "COALESCE(NULLIF(source_label, ''), #{legacy_source_label_expression})"
    end

    def source_label_sql_node
      sql_expression_node(source_label_expression)
    end

    def source_channel_expression
      <<~SQL.squish
        COALESCE(
          NULLIF(source_channel, ''),
          CASE
            WHEN NULLIF(utm_medium, '') IS NOT NULL THEN #{utm_medium_expression}
            WHEN NULLIF(referring_domain, '') IS NOT NULL THEN 'Referral'
            ELSE 'Direct'
          END
        )
      SQL
    end

    def source_channel_sql_node
      sql_expression_node(source_channel_expression)
    end

    def utm_medium_expression
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

    def normalize_label(value)
      Analytics::SourceResolver.resolve(referring_domain: value).source_label
    end

    def normalize_name(value)
      candidate = value.to_s.strip
      return Analytics::SourceResolver::DIRECT_LABEL if candidate.blank?

      Analytics::SourceResolver.canonical_label(candidate) ||
        Analytics::SourceResolver.resolve(referring_domain: candidate).source_label
    end

    def match_values(value)
      candidate = value.to_s.strip
      return [ Analytics::SourceResolver::DIRECT_LABEL ] if candidate.blank?

      [ candidate, normalize_name(candidate) ].compact_blank.uniq
    end

    def filter_scope(scope, source)
      values = match_values(source)
      scope.where(source_label_sql_node.in(values))
    end

    def mode_sql(mode)
      case mode
      when "channels"
        [ source_channel_expression, "LOWER(#{source_channel_expression}) LIKE ?" ]
      when "referrers"
        [ "COALESCE(referring_domain, '#{Analytics::SourceResolver::DIRECT_LABEL}')", "LOWER(COALESCE(referring_domain, '#{Analytics::SourceResolver::DIRECT_LABEL}')) LIKE ?" ]
      when "all"
        [ source_label_expression, "LOWER(#{source_label_expression}) LIKE ?" ]
      when "utm-medium"
        [ utm_medium_expression, "LOWER(#{utm_medium_expression}) LIKE ?" ]
      when "utm-source"
        [ "utm_source", "LOWER(utm_source) LIKE ?" ]
      when "utm-campaign"
        [ "utm_campaign", "LOWER(utm_campaign) LIKE ?" ]
      when "utm-content"
        [ "utm_content", "LOWER(utm_content) LIKE ?" ]
      when "utm-term", "search-terms"
        [ "utm_term", "LOWER(utm_term) LIKE ?" ]
      else
        [ source_label_expression, "LOWER(#{source_label_expression}) LIKE ?" ]
      end
    end

    def order_metrics(order_by, grouped_visit_ids, counts, range, query_or_filters, total, advanced_filters: [])
      query =
        if query_or_filters.is_a?(Analytics::Query)
          query_or_filters
        else
          Analytics::Query.new(filters: query_or_filters, advanced_filters: advanced_filters)
        end

      case order_by[0]
      when "percentage"
        counts.keys.index_with { |name| { percentage: (counts[name].to_f / total) } }
      when "bounce_rate", "visit_duration"
        metrics = Analytics::ReportMetrics.calculate_group_metrics(grouped_visit_ids, range, query)
        counts.keys.index_with { |name| metrics[name] || {} }
      else
        {}
      end
    end

    def goal_denominator_counts(query, mode:, search: nil)
      base_query = Analytics::Query.wrap(query)
        .without_goal_or_properties(property_filter: ->(key) { Analytics::Properties.filter_key?(key) })
        .with_option(:mode, mode)

      Analytics::SourcesDatasetQuery.payload(query: base_query, search: search).fetch(:results, []).each_with_object({}) do |row, counts|
        counts[row[:name].to_s] = row[:visitors].to_i
      end
    end

    def referrer_goal_denominator_counts(query, source, search: nil)
      base_query = Analytics::Query.wrap(query)
        .without_goal_or_properties(property_filter: ->(key) { Analytics::Properties.filter_key?(key) })

      Analytics::ReferrersDatasetQuery.payload(query: base_query, source: source, search: search).fetch(:results, []).each_with_object({}) do |row, counts|
        counts[row[:name].to_s] = row[:visitors].to_i
      end
    end

    def filter_groups!(mode, grouped_visit_ids, counts, comparison_names)
      return if comparison_names.empty?

      grouped_visit_ids.select! { |name, _| comparison_names.include?(formatted_name(mode, name)) }
      counts.select! { |name, _| comparison_names.include?(formatted_name(mode, name)) }
    end

    def formatted_name(mode, name)
      label = name.to_s
      return mode.start_with?("utm-") ? "(not set)" : "(none)" if label.strip.empty?

      label
    end

    def debug_payload(query, source)
      query = Analytics::Query.wrap(query)
      range, = Analytics::Ranges.range_and_interval_for(query.time_range_key, nil, query)
      normalized_source = normalize_name(source)
      visits = Analytics::VisitScope
        .visits(range, query)
        .yield_self { |scope| filter_scope(scope, source) }

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
        channels: sorted_count_rows(visits.group(Arel.sql(source_channel_expression)).count("DISTINCT visitor_token")),
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

    def debug_previews(grouped_visit_ids)
      ids_to_source = {}
      grouped_visit_ids.each do |name, ids|
        ids.each { |visit_id| ids_to_source[visit_id] = formatted_name("all", name) }
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

    private
      def sql_expression_node(expression)
        Arel::Nodes::Grouping.new(Arel.sql(expression))
      end

      def sorted_count_rows(counts, limit: 10)
        counts
          .reject { |value, count| value.to_s.strip.empty? || count.to_i <= 0 }
          .sort_by { |value, count| [ -count.to_i, value.to_s ] }
          .first(limit)
          .map { |value, count| { value: value.to_s, count: count.to_i } }
      end
  end
end
