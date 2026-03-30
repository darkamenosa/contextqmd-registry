class Ahoy::Event < AnalyticsRecord
  include Ahoy::QueryMethods
  include Ahoy::Event::Filters

  self.table_name = "ahoy_events"

  belongs_to :visit
  belongs_to :user, class_name: "::Identity", optional: true
  belongs_to :analytics_site, class_name: "Analytics::Site", optional: true
  belongs_to :analytics_site_boundary, class_name: "Analytics::SiteBoundary", optional: true

  scope :for_analytics_site, ->(site = ::Analytics::Current.site_or_default) { Analytics::Scope.apply(all, site:) }
  before_validation :assign_analytics_site_scope, on: :create

  private
    def assign_analytics_site_scope
      self.analytics_site ||= visit&.analytics_site || ::Analytics::Current.site_or_default
      self.analytics_site_boundary ||= visit&.analytics_site_boundary || ::Analytics::Current.site_boundary_or_default if analytics_site.present?
    end
end
