# frozen_string_literal: true

module Analytics::Locations
  class << self
    def location_label(city: nil, region: nil, country: nil, order: :city_first, fallback: nil)
      parts =
        case order
        when :country_first
          [ country, region, city ]
        else
          [ city, region, country ]
        end

      label = unique_location_parts(parts).join(", ")
      label.presence || fallback.to_s.presence
    end

    def map_from_counts(counts)
      total = counts.values.sum
      results = counts
        .sort_by { |_, visitors| -visitors }
        .filter_map do |(code, visitors)|
          next if code.blank?

          normalized = code.to_s.upcase
          country = ::ISO3166::Country.new(normalized)
          next unless country

          {
            alpha3: country.alpha3,
            alpha2: country.alpha2,
            numeric: country.number,
            code: normalized,
            name: short_country_name(country),
            visitors: visitors
          }
        end

      { map: { results: results, meta: { total: total } } }
    end

    def emoji_flag_for(code)
      return nil if code.blank?

      iso2 = code.to_s.upcase
      return nil unless iso2.match?(/\A[A-Z]{2}\z/)

      base = 0x1F1E6
      iso2.each_char.map { |char| (base + (char.ord - "A".ord)).chr(Encoding::UTF_8) }.join
    rescue StandardError
      nil
    end

    def country_flags_for_grouped(grouped_visit_ids, visits_relation, dimension, query_or_filters, advanced_filters: [])
      return {} if grouped_visit_ids.blank?

      query =
        if query_or_filters.is_a?(Analytics::Query)
          query_or_filters
        else
          Analytics::Query.new(filters: query_or_filters, advanced_filters: advanced_filters)
        end

      if query.filter_value(:country).present?
        flag = emoji_flag_for(Ahoy::Visit.normalize_country_code(query.filter_value(:country)))
        grouped_visit_ids.keys.each_with_object({}) { |name, result| result[name] = flag }
      else
        all_ids = grouped_visit_ids.values.flatten.uniq
        return {} if all_ids.empty?

        pairs = visits_relation.where(id: all_ids).group(dimension, Arel.sql(country_code_expression)).count
        best = {}

        pairs.each do |(name, country), count|
          next if name.blank?

          previous = best[name]
          if previous.nil? || count.to_i > previous[:count].to_i
            best[name] = { country: country, count: count.to_i }
          end
        end

        best.transform_values { |value| emoji_flag_for(value[:country].to_s.upcase) }
      end
    rescue StandardError
      {}
    end

    def alpha3_for(code)
      country = ::ISO3166::Country.new(code)
      country&.alpha3 || code
    end

    def country_code_expression
      "NULLIF(country_code, '')"
    end

    def country_name_for(code)
      Analytics::Country::Label.name_for(code) || code
    end

    def short_country_name(country)
      return "" unless country

      name = if country.respond_to?(:common_name) && country.common_name.present?
        country.common_name
      else
        country.iso_short_name.to_s
      end

      name = name.to_s.gsub(/\s*\(the\)\s*\z/i, "").gsub(/\s{2,}/, " ").strip
      case name
      when "Viet Nam" then "Vietnam"
      when "Korea (Republic of)" then "South Korea"
      when "Korea (Democratic People's Republic of)" then "North Korea"
      else
        name
      end
    end

    def goal_denominator_counts(query, mode:, search: nil)
      base_query = Analytics::Query.wrap(query)
        .without_goal_or_properties(property_filter: ->(key) { Analytics::Properties.filter_key?(key) })
        .with_option(:mode, mode)

      Analytics::LocationsDatasetQuery.payload(query: base_query, search: search).fetch(:results, []).each_with_object({}) do |row, counts|
        counts[row[:name].to_s] = row[:visitors].to_i
        counts[row[:code].to_s] = row[:visitors].to_i if row[:code].present?
      end
    end

    def filter_groups!(mode, grouped_visit_ids, counts, comparison_names, comparison_codes)
      return if comparison_names.empty? && comparison_codes.empty?

      matcher = lambda do |key|
        if mode == "countries"
          code = Ahoy::Visit.normalize_country_code(key)
          comparison_codes.include?(code) || comparison_names.include?(country_name_for(code))
        else
          label = key.to_s.presence || "(unknown)"
          comparison_names.include?(label)
        end
      end

      grouped_visit_ids.select! { |key, _| matcher.call(key) }
      counts.select! { |key, _| matcher.call(key) }
    end

    private
      def unique_location_parts(parts)
        parts.each_with_object([]) do |part, values|
          normalized = part.to_s.squish
          next if normalized.blank?
          next if values.any? { |existing| existing.casecmp?(normalized) }

          values << normalized
        end
      end
  end
end
