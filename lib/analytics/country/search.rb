# frozen_string_literal: true

module Analytics
  module Country
    module Search
      extend self

      def alpha2_codes(query)
        raw = query.to_s.strip
        return [] if raw.blank?

        needle = normalize(raw)
        matches = ISO3166::Country.all.filter_map do |country|
          next unless searchable_values(country).any? { |value| normalize(value).include?(needle) }

          country.alpha2
        end

        alias_matches = Parser::ALIASES.each_with_object([]) do |(name, code), rows|
          rows << code if name.include?(needle)
        end

        exact = Parser.alpha2(raw)
        ([ exact ].compact + alias_matches + matches).uniq.sort
      end

      private
        def searchable_values(country)
          [
            country.alpha2,
            country.alpha3,
            country.iso_short_name,
            country.respond_to?(:common_name) ? country.common_name : nil,
            Label.name_for(country.alpha2),
            *Array(country.respond_to?(:unofficial_names) ? country.unofficial_names : nil)
          ].compact.uniq
        end

        def normalize(value)
          Parser.normalize(value)
        end
    end
  end
end
