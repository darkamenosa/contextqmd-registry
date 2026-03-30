# frozen_string_literal: true

class Analytics::AllowedEventProperty < AnalyticsRecord
  self.table_name = "analytics_allowed_event_properties"

  belongs_to :analytics_site, class_name: "Analytics::Site"

  validates :analytics_site, presence: true
  validates :property_name, presence: true, uniqueness: { scope: :analytics_site_id }

  before_validation :normalize_property_name

  scope :for_analytics_site, ->(site = ::Analytics::Current.site_or_default) { Analytics::Scope.apply(all, site:) }

  class << self
    def configured_for?(site = ::Analytics::Current.site_or_default)
      return false if site.blank?

      where(analytics_site_id: site.id).exists?
    end

    def configured_keys(site = ::Analytics::Current.site_or_default)
      return [] if site.blank?

      where(analytics_site_id: site.id).order(:property_name).pluck(:property_name)
    end

    def sync_keys!(keys, site:)
      raise ArgumentError, "site is required" if site.blank?

      normalized = Analytics::Lists.normalize_strings(keys)

      transaction do
        existing = for_analytics_site(site).index_by(&:property_name)

        normalized.each do |property_name|
          existing.delete(property_name) || create!(analytics_site: site, property_name: property_name)
        end

        existing.each_value(&:destroy!)
      end
    end
  end

  private
    def normalize_property_name
      self.property_name = property_name.to_s.strip.presence
    end
end
