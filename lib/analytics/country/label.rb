# frozen_string_literal: true

module Analytics
  module Country
    module Label
      extend self

      def name_for(code)
        alpha2 = Parser.alpha2(code)
        return nil if alpha2.blank?

        country = ISO3166::Country.new(alpha2)
        return nil unless country

        normalize_name(preferred_name(country))
      rescue StandardError
        nil
      end

      def normalize_name(value)
        name = value.to_s.gsub(/\s*\(the\)\s*\z/i, "").gsub(/\s{2,}/, " ").strip

        case name
        when "Viet Nam" then "Vietnam"
        when "Korea (Republic of)" then "South Korea"
        when "Korea (Democratic People's Republic of)" then "North Korea"
        else
          name
        end
      end

      private
        def preferred_name(country)
          if country.respond_to?(:common_name) && country.common_name.present?
            country.common_name
          else
            country.iso_short_name.to_s
          end
        end
    end
  end
end
