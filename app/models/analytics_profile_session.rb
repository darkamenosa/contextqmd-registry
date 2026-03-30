# frozen_string_literal: true

class AnalyticsProfileSession < AnalyticsRecord
  belongs_to :analytics_profile
  belongs_to :visit, class_name: "Ahoy::Visit"
  belongs_to :analytics_site, class_name: "Analytics::Site", optional: true

  before_validation :normalize_country_attributes

  scope :for_analytics_site, ->(site = ::Analytics::Current.site) { Analytics::Scope.apply(all, site:) }

  private
    def normalize_country_attributes
      resolved = Analytics::Country.resolve(country:, country_code:)
      self.country_code = resolved.code if respond_to?(:country_code=)
      self.country = resolved.name
      self.analytics_site_id ||= analytics_profile&.analytics_site_id || visit&.analytics_site_id
    end
end
