require "countries"

class AddCountryCodeFormatConstraints < ActiveRecord::Migration[8.0]
  class MigrationVisit < ActiveRecord::Base
    self.table_name = "ahoy_visits"
  end

  class MigrationProfileSession < ActiveRecord::Base
    self.table_name = "analytics_profile_sessions"
  end

  def up
    sanitize_country_codes!(MigrationVisit)
    sanitize_country_codes!(MigrationProfileSession)

    add_check_constraint(
      :ahoy_visits,
      "(country_code IS NULL) OR (country_code ~ '^[A-Z]{2}$')",
      name: "ahoy_visits_country_code_format"
    )

    add_check_constraint(
      :analytics_profile_sessions,
      "(country_code IS NULL) OR (country_code ~ '^[A-Z]{2}$')",
      name: "analytics_profile_sessions_country_code_format"
    )
  end

  def down
    remove_check_constraint :analytics_profile_sessions, name: "analytics_profile_sessions_country_code_format"
    remove_check_constraint :ahoy_visits, name: "ahoy_visits_country_code_format"
  end

  private
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

    def sanitize_country_codes!(model)
      model.find_each do |record|
        normalized = normalize_code(record.country_code)
        next if normalized == record.country_code

        record.update_columns(country_code: normalized)
      end
    end

    def normalize_code(value)
      raw = value.to_s.strip
      return nil if raw.blank?

      aliased = ALIASES[normalize(raw)]
      return aliased if aliased.present?

      country = ISO3166::Country.new(raw.upcase)
      return country.alpha2 if country&.alpha2

      if raw.upcase.match?(/\A[A-Z]{3}\z/)
        converted = ISO3166::Country.from_alpha3_to_alpha2(raw.upcase)
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
