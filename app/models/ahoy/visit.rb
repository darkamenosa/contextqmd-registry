class Ahoy::Visit < AnalyticsRecord
  self.table_name = "ahoy_visits"

  has_many :events, class_name: "Ahoy::Event"
  belongs_to :user, class_name: "::Identity", optional: true
  belongs_to :analytics_profile, class_name: "AnalyticsProfile", optional: true
  belongs_to :analytics_site, class_name: "Analytics::Site", optional: true
  belongs_to :analytics_site_boundary, class_name: "Analytics::SiteBoundary", optional: true
  scope :with_coordinates, -> { where.not(latitude: nil, longitude: nil) }
  scope :for_analytics_site, ->(site = ::Analytics::Current.site_or_default) { Analytics::Scope.apply(all, site:) }
  before_validation :assign_source_dimensions
  before_validation :assign_analytics_site_scope, on: :create

  # Analytics concerns
  include Ahoy::Visit::Constants
  include Ahoy::Visit::Countries
  include Ahoy::Visit::CacheKey

  def project_later(previous_profile_id: nil)
    Analytics::VisitProjectionJob.perform_later(self, previous_profile_id: previous_profile_id)
  end

  def project_now(previous_profile_id: nil)
    AnalyticsProfile::Projection.project_visit(self, previous_profile_id: previous_profile_id)
  end

  def resolve_profile_later(browser_id:, strong_keys:, occurred_at: nil, identity_snapshot: {})
    Analytics::ProfileResolutionJob.perform_later(
      self,
      browser_id: browser_id,
      strong_keys: strong_keys,
      occurred_at: occurred_at,
      identity_snapshot: identity_snapshot
    )
  end

  def resolve_profile_now(browser_id:, strong_keys:, occurred_at: nil, identity_snapshot: nil)
    AnalyticsProfile::Resolution.resolve(
      visit: self,
      browser_id: browser_id,
      strong_keys: strong_keys,
      occurred_at: occurred_at,
      identity_snapshot: identity_snapshot
    )
  end

  def assign_source_dimensions
    resolution = Analytics::SourceResolver.resolve(
      referrer: referrer,
      referring_domain: referring_domain,
      utm_source: utm_source,
      utm_medium: utm_medium,
      utm_campaign: utm_campaign,
      landing_page: landing_page,
      hostname: hostname
    )

    self.source_label = resolution.source_label
    self.source_kind = resolution.source_kind
    self.source_channel = resolution.source_channel
    self.source_favicon_domain = resolution.source_favicon_domain
    self.source_paid = resolution.source_paid
    self.source_rule_id = resolution.source_rule_id
    self.source_rule_version = resolution.source_rule_version
    self.source_match_strategy = resolution.source_match_strategy
  end

  def refresh_source_dimensions!
    assign_source_dimensions
    update_columns(source_dimension_attributes)
  end

  def source_dimension_attributes
    {
      source_label: source_label,
      source_kind: source_kind,
      source_channel: source_channel,
      source_favicon_domain: source_favicon_domain,
      source_paid: source_paid,
      source_rule_id: source_rule_id,
      source_rule_version: source_rule_version,
      source_match_strategy: source_match_strategy
    }
  end

  private
    def assign_analytics_site_scope
      self.analytics_site ||= ::Analytics::Current.site_or_default
      self.analytics_site_boundary ||= ::Analytics::Current.site_boundary_or_default if analytics_site.present?
    end
end
