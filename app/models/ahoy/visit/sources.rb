module Ahoy::Visit::Sources
  extend ActiveSupport::Concern

  class_methods do
    CHANNEL_CASE_SQL = <<~SQL.squish.freeze
      CASE
        WHEN lower(utm_source) ~ '(fb[_-]?ad|facebook[_-]?ads?|meta[-_]?ads?|instagram[_-]?ads?|ig[-_]?ads?|tiktok[-_]?ads?|tt[-_]?ads?|linkedin[-_]?ads?|twitter[-_]?ads?|x[-_]?ads?)' THEN 'Paid Social'
        WHEN lower(utm_medium) IN ('cpc','ppc','paid','ads') THEN 'Paid Search'
        WHEN lower(utm_medium) IN ('paid_social','social_paid') THEN 'Paid Social'
        WHEN lower(utm_medium) IN ('display','banner','expandable','interstitial','cpm') THEN 'Display'
        WHEN lower(utm_medium) = 'affiliate' THEN 'Affiliates'
        WHEN lower(utm_campaign) LIKE '%cross-network%' THEN 'Cross-network'
        WHEN (referring_domain ~* '(google\\.|bing\\.)' AND landing_page ILIKE '%gclid=%') THEN 'Paid Search'
        WHEN (referring_domain ~* '(google\\.|bing\\.)' AND landing_page ILIKE '%msclkid=%') THEN 'Paid Search'
        WHEN lower(utm_source) ~ '(adwords|googleads|ga-ads|bing-ads|msads|search-ads)' THEN 'Paid Search'
        WHEN lower(utm_medium) ~ 'e[-_ ]?mail|newsletter' THEN 'Email'
        WHEN lower(utm_source) ~ 'e[-_ ]?mail|newsletter' THEN 'Email'
        WHEN referring_domain ~* '(^|\\.)mail\\.google\\.com$|(^|\\.)gmail\\.' THEN 'Email'
        WHEN referring_domain ~* '(^|\\.)mail\\.yahoo\\.' THEN 'Email'
        WHEN referring_domain ~* '(^|\\.)outlook\\.|(^|\\.)live\\.|(^|\\.)office\\.com' THEN 'Email'
        WHEN lower(COALESCE(referring_domain, '')) IN ('', 'localhost')
             AND lower(COALESCE(utm_source, '')) ~ '(facebook|instagram|twitter|x$|x\\.com|linkedin|reddit|tiktok|discord|quora|weibo|vk(\\.com)?|pinterest)'
        THEN 'Organic Social'
        WHEN lower(COALESCE(referring_domain, '')) IN ('', 'localhost')
             AND lower(COALESCE(utm_source, '')) ~ '(google|bing|duckduckgo|yahoo|baidu|yandex|naver|seznam|sogou|startpage|perplexity|chatgpt)'
        THEN 'Organic Search'
        WHEN lower(COALESCE(referring_domain, '')) IN ('', 'localhost')
             AND lower(COALESCE(utm_source, '')) ~ '(youtube|youtu\\.be|vimeo|twitch|dailymotion|youku|bilibili)'
        THEN 'Organic Video'
        WHEN lower(COALESCE(utm_source, '')) IN ('direct','directlink','(direct)','none','(none)') THEN 'Direct'
        WHEN lower(COALESCE(utm_medium, '')) IN ('direct','directlink','(direct)','none','(none)') THEN 'Direct'
        WHEN referring_domain IS NULL OR referring_domain = '' THEN 'Direct'
        WHEN lower(COALESCE(referring_domain, '')) = lower(COALESCE(hostname, '')) THEN 'Direct'
        WHEN lower(COALESCE(referring_domain, '')) = lower(
          COALESCE(
            NULLIF(regexp_replace(landing_page, '^(https?://)([^/]+).*$','\\2'),''),
            ''
          )
        ) THEN 'Direct'
        WHEN lower(utm_medium) LIKE '%video%' THEN 'Organic Video'
        WHEN referring_domain ~* '(youtube\\.|youtu\\.be|vimeo\\.|twitch\\.|dailymotion\\.|youku\\.|bilibili\\.)' THEN 'Organic Video'
        WHEN (referring_domain ~* '(youtube\\.|youtu\\.be|vimeo\\.|twitch\\.|dailymotion\\.|youku\\.|bilibili\\.)'
              AND lower(utm_medium) ~ '(^.*cp.*|ppc|retargeting|paid.*)') THEN 'Paid Video'
        WHEN referring_domain ~* '(google\\.|bing\\.|duckduckgo\\.|yahoo\\.|baidu\\.|yandex\\.|naver\\.|seznam\\.|sogou\\.|startpage\\.|perplexity\\.|chatgpt\\.)' THEN 'Organic Search'
        WHEN referring_domain ~* '(facebook\\.|instagram\\.|twitter\\.|x\\.com|linkedin\\.|reddit\\.|tiktok\\.|discord\\.|quora\\.|weibo\\.|vk\\.com|pinterest\\.)' THEN 'Organic Social'
        WHEN lower(utm_medium) IN ('social','social-network','social-media','sm','social network','social media') THEN 'Organic Social'
        WHEN (lower(utm_campaign) ~ '(^|[^a-df-z])shop|shopping') AND lower(utm_medium) ~ '(^.*cp.*|ppc|retargeting|paid.*)' THEN 'Paid Shopping'
        WHEN lower(utm_campaign) ~ '(^|[^a-df-z])shop|shopping' THEN 'Organic Shopping'
        WHEN lower(utm_medium) = 'audio' THEN 'Audio'
        WHEN lower(utm_source) = 'sms' OR lower(utm_medium) = 'sms' THEN 'SMS'
        WHEN right(lower(utm_medium), 4) = 'push' OR lower(utm_medium) LIKE '%mobile%' OR lower(utm_medium) LIKE '%notification%' OR lower(utm_source) = 'firebase' THEN 'Mobile Push Notifications'
        WHEN lower(utm_medium) ~ '(^.*cp.*|ppc|retargeting|paid.*)' THEN 'Paid Other'
        WHEN lower(utm_source) IN ('github','stack','stackoverflow','hn','hackernews') OR referring_domain ~* '(github\\.|stackoverflow\\.|news\\.ycombinator\\.com$)' THEN 'Developer'
        ELSE 'Referral'
      END
    SQL
    def paid_source_search_regex
      "(adwords|googleads|ga-ads|bing-ads|msads|search-ads)"
    end

    def paid_source_social_regex
      "(fb[_-]?ad|facebook[_-]?ads?|meta[-_]?ads?|instagram[_-]?ads?|ig[-_]?ads?|tiktok[-_]?ads?|tt[-_]?ads?|linkedin[-_]?ads?|twitter[-_]?ads?|x[-_]?ads?)"
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

    def normalize_source_label(domain)
      host = domain.to_s.downcase.strip
      return "Direct / None" if host.blank?

      Analytics::SourceCatalog::SOURCE_MAP&.each do |label, regex|
        return label if host.match?(regex)
      end
      host
    end

    def domain_pattern_for_source_label(label)
      key = label.to_s.strip
      map = Analytics::SourceCatalog::SOURCE_MAP || {}
      return map[key]&.source if map[key]
      alt = key.gsub(" ", "")
      return map[alt]&.source if map[alt]
      nil
    end

    def alias_sources_map
      Rails.configuration.x.analytics.alias_sources_map || {}
    end

    def paid_sources_set
      Rails.configuration.x.analytics.paid_sources_set || Set.new
    end

    def direct_utm?(value)
      v = value.to_s.strip.downcase
      return false if v.empty?
      %w[direct directlink (direct) none (none)].include?(v)
    end

    def channel_case
      Arel.sql(CHANNEL_CASE_SQL)
    end

    def sources_payload(query, limit: nil, page: nil, search: nil, order_by: nil)
      mode = query[:mode] || "all"
      filters = query[:filters] || {}
      range, = Ahoy::Visit.range_and_interval_for(query[:period], nil, query)
      visits = Ahoy::Visit.scoped_visits(range, filters)
      goal = filters["goal"].presence

      expr, where_clause = case mode
      when "channels"
        [ CHANNEL_CASE_SQL, "LOWER(#{CHANNEL_CASE_SQL}) LIKE ?" ]
      when "referrers"
        [ "COALESCE(referring_domain, 'Direct / None')", "LOWER(COALESCE(referring_domain, 'Direct / None')) LIKE ?" ]
      when "all"
        [ "COALESCE(referring_domain, '')", nil ]
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
        [ "COALESCE(referring_domain, 'Direct / None')", "LOWER(COALESCE(referring_domain, 'Direct / None')) LIKE ?" ]
      end

      if limit && page
        pattern = search.present? ? Ahoy::Visit.like_contains(search) : nil
        rel = visits
        if mode == "channels" && pattern.present?
          pat = Ahoy::Visit.connection.quote(pattern)
          rel = rel.where(Arel.sql("LOWER((#{CHANNEL_CASE_SQL})) LIKE #{pat}"))
        elsif where_clause && pattern.present?
          rel = rel.where([ where_clause, pattern ])
        elsif mode == "all" && pattern.present?
          rel = rel.where(
            "LOWER(COALESCE(referring_domain, '')) LIKE ? OR LOWER(COALESCE(utm_source, '')) LIKE ?",
            pattern, pattern
          )
        end

        if mode == "all"
          expr_tag = "COALESCE(utm_source, '')"
          expr_dom = "COALESCE(referring_domain, '')"
          rows = rel
            .group(Arel.sql("#{expr_tag}, #{expr_dom}"))
            .pluck(Arel.sql("#{expr_tag}, #{expr_dom}, ARRAY_AGG(ahoy_visits.id)"))

          grouped_visit_ids = Hash.new { |h, k| h[k] = [] }
          rows.each do |tag, dom, ids|
            t = tag.to_s.strip
            d = dom.to_s.strip
            label = nil
            if d.present?
              brand = normalize_source_label(d)
              if %w[Gmail Outlook.com Yahoo! Mail Proton Mail iCloud Mail].include?(brand)
                label = brand
              end
            end
            if label.nil? && t.present?
              label = if direct_utm?(t)
                "Direct / None"
              else
                alias_sources_map[t.downcase].presence || t
              end
            end
            label ||= normalize_source_label(d)
            grouped_visit_ids[label].concat(ids)
          end

          if search.present?
            needle = search.downcase
            grouped_visit_ids.select! { |label, _| label.downcase.include?(needle) }
          end

          counts = Ahoy::Visit.unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits)
        else
          grouped_visit_ids = rel
            .group(Arel.sql(expr))
            .pluck(Arel.sql("#{expr}, ARRAY_AGG(ahoy_visits.id)"))
            .to_h

          counts = Ahoy::Visit.unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits)
          if mode.start_with?("utm-")
            grouped_visit_ids.delete(nil)
            counts.delete(nil)
            grouped_visit_ids.delete("(not set)")
            counts.delete("(not set)")
            grouped_visit_ids.reject! { |k, _| k.to_s.strip.empty? }
            counts.reject! { |k, _| k.to_s.strip.empty? }
          end
        end

        sorted_names = if goal.present?
          conversions_all, cr_all = Ahoy::Visit.conversions_and_rates(grouped_visit_ids, visits, range, filters, goal)
          Ahoy::Visit.order_names_with_conversions(conversions: conversions_all, cr: cr_all, order_by: order_by)
        else
          if order_by && %w[bounce_rate visit_duration].include?(order_by[0])
            metrics_all = Ahoy::Visit.calculate_group_metrics(grouped_visit_ids, range, filters)
            Ahoy::Visit.order_names(counts: counts, metrics_map: counts.keys.index_with { |n| metrics_all[n] || {} }, order_by: order_by)
          else
            Ahoy::Visit.order_names(counts: counts, metrics_map: {}, order_by: order_by)
          end
        end

        paged_names, has_more = Ahoy::Visit.paginate_names(sorted_names, limit: limit, page: page)

        page_visit_ids = grouped_visit_ids.slice(*paged_names)

        if goal.present?
          conversions, cr = Ahoy::Visit.conversions_and_rates(page_visit_ids, visits, range, filters, goal)
          results = paged_names.map do |name|
            label = begin
              empty_label = mode.start_with?("utm-") ? "(not set)" : "(none)"
              name.to_s.presence || empty_label
            end
            { name: label, visitors: conversions[name] || 0, conversion_rate: cr[name] }
          end
          { results: results, metrics: %i[visitors conversion_rate], meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query), metric_labels: { visitors: "Conversions", conversionRate: "Conversion Rate" } } }
        else
          group_metrics = Ahoy::Visit.calculate_group_metrics(page_visit_ids, range, filters)
          results = paged_names.map do |name|
            v = counts[name]
            {
              name: begin
                empty_label = mode.start_with?("utm-") ? "(not set)" : "(none)"
                name.to_s.presence || empty_label
              end,
              visitors: v,
              bounce_rate: group_metrics.dig(name, :bounce_rate),
              visit_duration: group_metrics.dig(name, :visit_duration)
            }
          end
          { results: results, metrics: %i[visitors bounce_rate visit_duration], meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query) } }
        end
      else
        counts = case mode
        when "channels"
          visits.group(channel_case).count("DISTINCT visitor_token").transform_keys { |k| k.to_s.presence || "Direct" }
        when "referrers"
          visits.group(Arel.sql("COALESCE(referring_domain, 'Direct / None')")).count("DISTINCT visitor_token")
        when "all"
          rows = visits
            .group(Arel.sql("COALESCE(utm_source, '')"), Arel.sql("COALESCE(referring_domain, '')"))
            .pluck(Arel.sql("COALESCE(utm_source, '')"), Arel.sql("COALESCE(referring_domain, '')"), Arel.sql("ARRAY_AGG(ahoy_visits.id)"))
          grouped_visit_ids = Hash.new { |h, k| h[k] = [] }
          rows.each do |tag, dom, ids|
            t = tag.to_s.strip
            d = dom.to_s.strip
            label = nil
            if d.present?
              brand = normalize_source_label(d)
              if %w[Gmail Outlook.com Yahoo! Mail Proton Mail iCloud Mail].include?(brand)
                label = brand
              end
            end
            if label.nil? && t.present?
              label = if direct_utm?(t)
                "Direct / None"
              else
                alias_sources_map[t.downcase].presence || t
              end
            end
            label ||= normalize_source_label(d)
            grouped_visit_ids[label].concat(ids)
          end
          Ahoy::Visit.unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits)
        when "utm-medium"
          buckets = visits.group(Arel.sql(utm_medium_expr)).count("DISTINCT visitor_token")
          buckets.delete("(not set)")
          buckets
        when "utm-source"
          buckets = visits.group(:utm_source).count("DISTINCT visitor_token")
          buckets.delete("")
          buckets
        when "utm-campaign"
          buckets = visits.group(:utm_campaign).count("DISTINCT visitor_token")
          buckets.delete("")
          buckets
        when "utm-content"
          buckets = visits.group(:utm_content).count("DISTINCT visitor_token")
          buckets.delete("")
          buckets
        when "utm-term", "search-terms"
          buckets = visits.group(:utm_term).count("DISTINCT visitor_token")
          buckets.delete("")
          buckets
        else
          visits.group(Arel.sql("COALESCE(referring_domain, 'Direct / None')")).count("DISTINCT visitor_token")
        end

        rows = counts.sort_by { |_, v| -v }.map do |(name, v)|
          label = name.to_s
          if label.strip.empty?
            label = mode.start_with?("utm-") ? "(not set)" : "(none)"
          end
          { name: label, visitors: v }
        end
        { results: rows, metrics: %i[visitors], meta: { has_more: false, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query) } }
      end
    end

    def referrers_payload(query, source, limit: nil, page: nil, search: nil, order_by: nil)
      range, = Ahoy::Visit.range_and_interval_for(query[:period], nil, query)
      filters = query[:filters] || {}
      goal = filters["goal"].presence

      s_down = source.to_s.downcase.strip
      direct = (s_down == "direct / none" || s_down == "(none)" || s_down == "direct" || s_down == "none")

      base_visits = Ahoy::Visit.scoped_visits(range, filters)
      visits = if direct
        base_visits.where(referring_domain: [ nil, "" ])
      else
        if (pattern = domain_pattern_for_source_label(source))
          aliases = alias_sources_map.select { |k, v| v.to_s.downcase == s_down }.keys
          if aliases.any?
            base_visits.where(
              "referring_domain ~* ? OR LOWER(utm_source) IN (?) OR LOWER(utm_source) LIKE ?",
              pattern, aliases, "#{s_down}%"
            )
          else
            base_visits.where(
              "referring_domain ~* ? OR LOWER(utm_source) = ? OR LOWER(utm_source) LIKE ?",
              pattern, s_down, "#{s_down}%"
            )
          end
        elsif source.include?(".")
          base_visits.where("referring_domain = ? OR LOWER(utm_source) = ?", source, s_down)
        else
          like = Ahoy::Visit.like_contains(s_down)
          base_visits.where("LOWER(referring_domain) LIKE ? OR LOWER(utm_source) LIKE ?", like, like)
        end
      end

      if direct
        counts = { "Direct / None" => visits.count }
        if limit && page
          grouped_visit_ids = { "Direct / None" => visits.pluck(:id) }
          if goal.present?
            conversions, cr = Ahoy::Visit.conversions_and_rates(grouped_visit_ids, visits, range, filters, goal)
            rows = counts.map { |name, _n| { name: name, visitors: conversions[name] || 0, conversion_rate: cr[name] } }
            { results: rows, metrics: %i[visitors conversion_rate], meta: { has_more: false, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query), metric_labels: { visitors: "Conversions", conversionRate: "Conversion Rate" } } }
          else
            metrics = Ahoy::Visit.calculate_group_metrics(grouped_visit_ids, range, filters)
            rows = counts.map { |name, n| { name: name, visitors: n, bounce_rate: metrics.dig(name, :bounce_rate), visit_duration: metrics.dig(name, :visit_duration) } }
            { results: rows, metrics: %i[visitors bounce_rate visit_duration], meta: { has_more: false, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query) } }
          end
        else
          rows = counts.sort_by { |_, v| -v }.map { |(name, v)| { name: name, visitors: v } }
          { results: rows, metrics: %i[visitors], meta: { has_more: false, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query) } }
        end
      else
        expr = "COALESCE(referrer, 'Direct / None')"
        pattern = search.present? ? Ahoy::Visit.like_contains(search) : nil

        if limit && page
          rel = visits
          rel = rel.where("LOWER(referrer) LIKE ?", pattern) if pattern.present?
          grouped_visit_ids = rel.group(Arel.sql(expr)).pluck(Arel.sql("#{expr}, ARRAY_AGG(ahoy_visits.id)")).to_h
          counts = Ahoy::Visit.unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits)

          sorted_names = if goal.present?
            conversions_all, cr_all = Ahoy::Visit.conversions_and_rates(grouped_visit_ids, visits, range, filters, goal)
            Ahoy::Visit.order_names_with_conversions(conversions: conversions_all, cr: cr_all, order_by: order_by)
          else
            if order_by && %w[bounce_rate visit_duration].include?(order_by[0])
              metrics_all = Ahoy::Visit.calculate_group_metrics(grouped_visit_ids, range, filters)
              Ahoy::Visit.order_names(counts: counts, metrics_map: counts.keys.index_with { |n| metrics_all[n] || {} }, order_by: order_by)
            else
              Ahoy::Visit.order_names(counts: counts, metrics_map: {}, order_by: order_by)
            end
          end

          paged_names, has_more = Ahoy::Visit.paginate_names(sorted_names, limit: limit, page: page)

          page_visit_ids = grouped_visit_ids.slice(*paged_names)
          if goal.present?
            conversions, cr = Ahoy::Visit.conversions_and_rates(page_visit_ids, visits, range, filters, goal)
            results = paged_names.map { |name| { name: name, visitors: conversions[name] || 0, conversion_rate: cr[name] } }
            { results: results, metrics: %i[visitors conversion_rate], meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query), metric_labels: { visitors: "Conversions", conversionRate: "Conversion Rate" } } }
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
            { results: results, metrics: %i[visitors bounce_rate visit_duration], meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query) } }
          end
        else
          counts = visits.group(Arel.sql(expr)).count
          rows = counts.sort_by { |_, v| -v }.map { |(name, v)| { name: name.to_s.presence || "(none)", visitors: v } }
          { results: rows, metrics: %i[visitors], meta: { has_more: false, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query) } }
        end
      end
    end
  end
end
