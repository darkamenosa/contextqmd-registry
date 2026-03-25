module Ahoy::Visit::Locations
  extend ActiveSupport::Concern

  class_methods do
    def locations_payload(query, limit: nil, page: nil, search: nil, order_by: nil)
      mode = query[:mode] || "map"
      filters = query[:filters] || {}
      advanced_filters = query[:advanced_filters] || []
      comparison_names = Ahoy::Visit.comparison_names_filter(query)
      comparison_codes = Ahoy::Visit.comparison_codes_filter(query)
      range, = Ahoy::Visit.range_and_interval_for(query[:period], nil, query)
      visits = Ahoy::Visit.scoped_visits(range, filters, advanced_filters: advanced_filters)
      goal = filters["goal"].presence

      case mode
      when "map"
        counts = visits.group(:country).count("DISTINCT visitor_token")
        map_from_counts(counts)
      when "countries"
        if limit && page
          expr = "COALESCE(country, '(unknown)')"
          pattern = search.present? ? Ahoy::Visit.like_contains(search) : nil
          rel = visits
          rel = rel.where("LOWER(COALESCE(country, '(unknown)')) LIKE ?", pattern) if pattern.present?
          grouped_visit_ids = rel.group(Arel.sql(expr)).pluck(Arel.sql("#{expr}, ARRAY_AGG(ahoy_visits.id)")).to_h
          counts = Ahoy::Visit.unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits)
          filter_location_groups!(
            "countries",
            grouped_visit_ids,
            counts,
            comparison_names,
            comparison_codes
          )
          total = Ahoy::Visit.percentage_total_visitors(visits)

          if goal.present?
            denominator_counts = goal_denominator_counts_for_locations(query, mode: mode, search: search)
            conversions, cr = Ahoy::Visit.conversions_and_rates(grouped_visit_ids, visits, range, filters, goal, advanced_filters: advanced_filters, denominator_counts: denominator_counts)
            sorted_names = Ahoy::Visit.order_names_with_conversions(conversions: conversions, cr: cr, order_by: order_by)

            paged_names, has_more = Ahoy::Visit.paginate_names(sorted_names, limit: limit, page: page)

            items = paged_names.map do |code|
              code_str = code.to_s
              name = if code_str.present? && code_str != "(unknown)"
                c = ::ISO3166::Country.new(code_str.upcase)
                c ? short_country_name(c) : code_str
              else
                "(unknown)"
              end
              { name: name, code: code_str != "(unknown)" ? code_str : nil, visitors: conversions[code] || 0, conversion_rate: Ahoy::Visit.goal_conversion_rate(conversions[code] || 0, denominator_counts[name]) }.compact
            end
            { results: items, metrics: %i[visitors conversion_rate], meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query), metric_labels: { visitors: "Conversions", conversionRate: "Conversion Rate" } } }
          else
            sorted_names = begin
              if order_by && order_by[0] == "percentage"
                perc = counts.keys.index_with { |k| { percentage: (counts[k].to_f / total) } }
                Ahoy::Visit.order_names(counts: counts, metrics_map: perc, order_by: order_by)
              else
                Ahoy::Visit.order_names(counts: counts, metrics_map: {}, order_by: order_by)
              end
            end

            paged_names, has_more = Ahoy::Visit.paginate_names(sorted_names, limit: limit, page: page)

            items = paged_names.map do |code|
              v = counts[code]
              code_str = code.to_s
              name = if code_str.present? && code_str != "(unknown)"
                c = ::ISO3166::Country.new(code_str.upcase)
                c ? short_country_name(c) : code_str
              else
                "(unknown)"
              end
              { name: name, code: code_str != "(unknown)" ? code_str : nil, visitors: v, percentage: (v.to_f / total).round(3) }.compact
            end
            { results: items, metrics: %i[visitors percentage], meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query), metric_labels: { percentage: "Percentage" } } }
          end
        else
          counts = visits.group(:country).count("DISTINCT visitor_token")
          total = Ahoy::Visit.percentage_total_visitors(visits)
          items = counts.map do |code, v|
            code_str = code.to_s
            if code_str.present?
              c = ::ISO3166::Country.new(code_str.upcase)
              if c
                { name: short_country_name(c), code: c.alpha2, visitors: v, percentage: (v.to_f / total).round(3) }
              else
                { name: code_str, visitors: v, percentage: (v.to_f / total).round(3) }
              end
            else
              { name: "(unknown)", visitors: v, percentage: (v.to_f / total).round(3) }
            end
          end
          items = items.sort_by { |it| [ -it[:visitors].to_i, it[:name].to_s ] }
          { results: items, metrics: %i[visitors percentage], meta: { has_more: false, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query), metric_labels: { percentage: "Percentage" } } }
        end
      when "regions"
        if limit && page
          expr = "COALESCE(region, '(unknown)')"
          pattern = search.present? ? Ahoy::Visit.like_contains(search) : nil
          rel = visits
          rel = rel.where("LOWER(COALESCE(region, '(unknown)')) LIKE ?", pattern) if pattern.present?
          grouped_visit_ids = rel.group(Arel.sql(expr)).pluck(Arel.sql("#{expr}, ARRAY_AGG(ahoy_visits.id)")).to_h
          counts = Ahoy::Visit.unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits)
          filter_location_groups!(
            "regions",
            grouped_visit_ids,
            counts,
            comparison_names,
            comparison_codes
          )
          total = Ahoy::Visit.percentage_total_visitors(visits)

          if goal.present?
            denominator_counts = goal_denominator_counts_for_locations(query, mode: mode, search: search)
            conversions, cr = Ahoy::Visit.conversions_and_rates(grouped_visit_ids, visits, range, filters, goal, advanced_filters: advanced_filters, denominator_counts: denominator_counts)
            sorted_names = Ahoy::Visit.order_names_with_conversions(conversions: conversions, cr: cr, order_by: order_by)

            paged_names, has_more = Ahoy::Visit.paginate_names(sorted_names, limit: limit, page: page)
            flags_by_region = country_flags_for_grouped(grouped_visit_ids.slice(*paged_names), visits, :region, filters)
            results = paged_names.map do |name|
              label = name.to_s.presence || "(none)"
              { name: label, visitors: conversions[name] || 0, conversion_rate: Ahoy::Visit.goal_conversion_rate(conversions[name] || 0, denominator_counts[label]), country_flag: flags_by_region[name] }.compact
            end
            { results: results, metrics: %i[visitors conversion_rate], meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query), metric_labels: { visitors: "Conversions", conversionRate: "Conversion Rate" } } }
          else
            metrics_map =
              if order_by&.first == "percentage"
                counts.keys.index_with { |name| { percentage: (counts[name].to_f / total) } }
              else
                {}
              end
            sorted_names = Ahoy::Visit.order_names(counts: counts, metrics_map: metrics_map, order_by: order_by)

            paged_names, has_more = Ahoy::Visit.paginate_names(sorted_names, limit: limit, page: page)
            flags_by_region = country_flags_for_grouped(grouped_visit_ids.slice(*paged_names), visits, :region, filters)
            results = paged_names.map do |name|
              v = counts[name]
              { name: name.to_s.presence || "(none)", visitors: v, percentage: (v.to_f / total).round(3), country_flag: flags_by_region[name] }.compact
            end
            { results: results, metrics: %i[visitors percentage], meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query), metric_labels: { percentage: "Percentage" } } }
          end
        else
          counts = visits.group(:region).count("DISTINCT visitor_token")
          total = Ahoy::Visit.percentage_total_visitors(visits)
          flags_by_region = if filters[:country].present?
            code = filters[:country].to_s.upcase
            flag = emoji_flag_for(code)
            counts.keys.each_with_object({}) { |r, h| h[r] = flag }
          else
            pairs = visits.group(:region, :country).count("DISTINCT visitor_token")
            dominant = Hash.new { |h, k| h[k] = { country: nil, count: -1 } }
            pairs.each do |(region, country), c|
              next if region.blank?
              cur = dominant[region]
              if c.to_i > cur[:count].to_i
                dominant[region] = { country: country, count: c.to_i }
              end
            end
            dominant.transform_values { |v| emoji_flag_for(v[:country].to_s.upcase) }
          end

          rows = counts.sort_by { |_, v| -v.to_i }.map do |(name, v)|
            label = name.to_s.presence || "(unknown)"
            h = { name: label, visitors: v, percentage: (v.to_f / total).round(3) }
            flag = flags_by_region[name]
            flag.present? ? h.merge(country_flag: flag) : h
          end
          { results: rows, metrics: %i[visitors percentage], meta: { has_more: false, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query), metric_labels: { percentage: "Percentage" } } }
        end
      when "cities"
        if limit && page
          expr = "COALESCE(city, '(unknown)')"
          pattern = search.present? ? Ahoy::Visit.like_contains(search) : nil
          rel = visits
          rel = rel.where("LOWER(COALESCE(city, '(unknown)')) LIKE ?", pattern) if pattern.present?
          grouped_visit_ids = rel.group(Arel.sql(expr)).pluck(Arel.sql("#{expr}, ARRAY_AGG(ahoy_visits.id)")).to_h
          counts = Ahoy::Visit.unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits)
          filter_location_groups!(
            "cities",
            grouped_visit_ids,
            counts,
            comparison_names,
            comparison_codes
          )
          total = Ahoy::Visit.percentage_total_visitors(visits)

          if goal.present?
            denominator_counts = goal_denominator_counts_for_locations(query, mode: mode, search: search)
            conversions, cr = Ahoy::Visit.conversions_and_rates(grouped_visit_ids, visits, range, filters, goal, advanced_filters: advanced_filters, denominator_counts: denominator_counts)
            sorted_names = Ahoy::Visit.order_names_with_conversions(conversions: conversions, cr: cr, order_by: order_by)

            paged_names, has_more = Ahoy::Visit.paginate_names(sorted_names, limit: limit, page: page)
            flags_by_city = country_flags_for_grouped(grouped_visit_ids.slice(*paged_names), visits, :city, filters)
            results = paged_names.map do |name|
              label = name.to_s.presence || "(none)"
              { name: label, visitors: conversions[name] || 0, conversion_rate: Ahoy::Visit.goal_conversion_rate(conversions[name] || 0, denominator_counts[label]), country_flag: flags_by_city[name] }.compact
            end
            { results: results, metrics: %i[visitors conversion_rate], meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query), metric_labels: { visitors: "Conversions", conversionRate: "Conversion Rate" } } }
          else
            metrics_map =
              if order_by&.first == "percentage"
                counts.keys.index_with { |name| { percentage: (counts[name].to_f / total) } }
              else
                {}
              end
            sorted_names = Ahoy::Visit.order_names(counts: counts, metrics_map: metrics_map, order_by: order_by)

            paged_names, has_more = Ahoy::Visit.paginate_names(sorted_names, limit: limit, page: page)
            flags_by_city = country_flags_for_grouped(grouped_visit_ids.slice(*paged_names), visits, :city, filters)
            results = paged_names.map do |name|
              v = counts[name]
              { name: name.to_s.presence || "(none)", visitors: v, percentage: (v.to_f / total).round(3), country_flag: flags_by_city[name] }.compact
            end
            { results: results, metrics: %i[visitors percentage], meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query), metric_labels: { percentage: "Percentage" } } }
          end
        else
          counts = visits.group(:city).count("DISTINCT visitor_token")
          total = Ahoy::Visit.percentage_total_visitors(visits)
          flags_by_city = if filters[:country].present?
            code = filters[:country].to_s.upcase
            flag = emoji_flag_for(code)
            counts.keys.each_with_object({}) { |c, h| h[c] = flag }
          else
            pairs = visits.group(:city, :country).count("DISTINCT visitor_token")
            dominant = Hash.new { |h, k| h[k] = { country: nil, count: -1 } }
            pairs.each do |(city, country), c|
              next if city.blank?
              cur = dominant[city]
              if c.to_i > cur[:count].to_i
                dominant[city] = { country: country, count: c.to_i }
              end
            end
            dominant.transform_values { |v| emoji_flag_for(v[:country].to_s.upcase) }
          end

          rows = counts.sort_by { |_, v| -v.to_i }.map do |(name, v)|
            label = name.to_s.presence || "(unknown)"
            h = { name: label, visitors: v, percentage: (v.to_f / total).round(3) }
            flag = flags_by_city[name]
            flag.present? ? h.merge(country_flag: flag) : h
          end
          { results: rows, metrics: %i[visitors percentage], meta: { has_more: false, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query), metric_labels: { percentage: "Percentage" } } }
        end
      else
        counts = visits.group(:country).count
        rows = counts.sort_by { |_, v| -v }.map { |(name, v)| { name: name.to_s.presence || "(none)", visitors: v } }
        { results: rows, metrics: %i[visitors], meta: { has_more: false, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query) } }
      end
    end

    def map_from_counts(counts)
      total = counts.values.sum
      results = counts
        .sort_by { |_, v| -v }
        .filter_map do |(code, visitors)|
          next if code.blank?
          normalized = code.to_s.upcase
          country = ::ISO3166::Country.new(normalized)
          next unless country
          { alpha3: country.alpha3, alpha2: country.alpha2, numeric: country.number, code: normalized, name: short_country_name(country), visitors: visitors }
        end
      { map: { results: results, meta: { total: total } } }
    end

    def emoji_flag_for(code)
      return nil if code.blank?
      iso2 = code.to_s.upcase
      return nil unless iso2.match?(/\A[A-Z]{2}\z/)
      base = 0x1F1E6
      iso2.each_char.map { |ch| (base + (ch.ord - "A".ord)).chr(Encoding::UTF_8) }.join
    rescue
      nil
    end

    def country_flags_for_grouped(grouped_visit_ids, visits_relation, dimension, filters)
      return {} if grouped_visit_ids.blank?
      if filters[:country].present?
        flag = emoji_flag_for(filters[:country].to_s.upcase)
        grouped_visit_ids.keys.each_with_object({}) { |name, h| h[name] = flag }
      else
        all_ids = grouped_visit_ids.values.flatten.uniq
        if all_ids.empty?
          {}
        else
          pairs = visits_relation.where(id: all_ids).group(dimension, :country).count
          best = {}
          pairs.each do |(name, country), c|
            next if name.blank?
            prev = best[name]
            if prev.nil? || c.to_i > prev[:count].to_i
              best[name] = { country: country, count: c.to_i }
            end
          end
          best.transform_values { |v| emoji_flag_for(v[:country].to_s.upcase) }
        end
      end
    rescue
      {}
    end

    def alpha3_for(code)
      country = ::ISO3166::Country.new(code)
      country&.alpha3 || code
    end

    def country_name_for(code)
      country = ::ISO3166::Country.new(code)
      country ? short_country_name(country) : code
    end

    def short_country_name(country)
      return "" unless country
      name = country.respond_to?(:common_name) && country.common_name.present? ? country.common_name : country.iso_short_name.to_s
      name = name.to_s.gsub(/\s*\(the\)\s*\z/i, "").gsub(/\s{2,}/, " ").strip
      case name
      when "Viet Nam" then "Vietnam"
      when "Korea (Republic of)" then "South Korea"
      when "Korea (Democratic People's Republic of)" then "North Korea"
      else
        name
      end
    end

    def goal_denominator_counts_for_locations(query, mode:, search: nil)
      base_query = Ahoy::Visit.query_without_goal_and_props(query).merge(mode: mode)
      payload = locations_payload(base_query, search: search)
      payload.fetch(:results, []).each_with_object({}) do |row, counts|
        counts[row[:name].to_s] = row[:visitors].to_i
        counts[row[:code].to_s] = row[:visitors].to_i if row[:code].present?
      end
    end

    def filter_location_groups!(mode, grouped_visit_ids, counts, comparison_names, comparison_codes)
      return if comparison_names.empty? && comparison_codes.empty?

      matcher = lambda do |key|
        if mode == "countries"
          code = key.to_s.upcase
          comparison_codes.include?(code) || comparison_names.include?(country_name_for(code))
        else
          label = key.to_s.presence || "(unknown)"
          comparison_names.include?(label)
        end
      end

      grouped_visit_ids.select! { |key, _| matcher.call(key) }
      counts.select! { |key, _| matcher.call(key) }
    end
  end
end
