# frozen_string_literal: true

module Analytics
  module Country
    module Parser
      extend self

      ALIASES = {
        "uk" => "GB",
        "great britain" => "GB",
        "england" => "GB",
        "uae" => "AE",
        "u a e" => "AE",
        "south korea" => "KR",
        "north korea" => "KP",
        "dr congo" => "CD",
        "drc" => "CD",
        "democratic republic of congo" => "CD",
        "cote d ivoire" => "CI",
        "ivory coast" => "CI"
      }.freeze

      def alpha2(value)
        raw = value.to_s.strip
        return nil if raw.blank?

        aliased = ALIASES[normalize(raw)]
        return aliased if aliased.present?

        country = ISO3166::Country.new(raw.upcase)
        return country.alpha2 if country&.alpha2.present?

        alpha3 = raw.upcase
        if alpha3.match?(/\A[A-Z]{3}\z/)
          converted = ISO3166::Country.from_alpha3_to_alpha2(alpha3)
          return converted if converted.present?
        end

        found = ISO3166::Country.find_country_by_any_name(raw)
        found&.alpha2
      rescue StandardError
        nil
      end

      def normalize(value)
        value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
      end
    end
  end
end
