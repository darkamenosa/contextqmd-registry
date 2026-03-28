# frozen_string_literal: true

class AnalyticsProfileSession < AnalyticsRecord
  belongs_to :analytics_profile
  belongs_to :visit, class_name: "Ahoy::Visit"

  before_validation :normalize_country_attributes

  private
    def normalize_country_attributes
      resolved = Analytics::Country.resolve(country:, country_code:)
      self.country_code = resolved.code if respond_to?(:country_code=)
      self.country = resolved.name
    end
end
