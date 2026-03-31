require "digest"
require "thread"

class Ahoy::Visit < AnalyticsRecord
  self.table_name = "ahoy_visits"

  PROFILE_RESOLUTION_COALESCE_WINDOW = 1.second
  VISIT_PROJECTION_COALESCE_WINDOW = 1.second

  ENQUEUE_MARKERS_MUTEX = Mutex.new
  ENQUEUE_MARKERS = {}

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
  include Ahoy::Visit::AnalyticsIngest

  def project_later(previous_profile_id: nil)
    if should_enqueue_visit_projection?(previous_profile_id:)
      Analytics::VisitProjectionJob.perform_later(self, previous_profile_id: previous_profile_id)
    end
  end

  def project_now(previous_profile_id: nil)
    AnalyticsProfile::Projection.project_visit(self, previous_profile_id: previous_profile_id)
  end

  def resolve_profile_later(browser_id:, strong_keys:, occurred_at: nil)
    if should_enqueue_profile_resolution?(browser_id:, strong_keys:)
      Analytics::ProfileResolutionJob.perform_later(
        self,
        browser_id: browser_id,
        strong_keys: strong_keys,
        occurred_at: occurred_at
      )
    end
  end

  def resolve_profile_now(browser_id:, strong_keys:, occurred_at: nil)
    AnalyticsProfile::Resolution.resolve(
      visit: self,
      browser_id: browser_id,
      strong_keys: strong_keys,
      occurred_at: occurred_at
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
    def should_enqueue_profile_resolution?(browser_id:, strong_keys:)
      write_coalesced_enqueue_marker(
        profile_resolution_cache_key(browser_id:, strong_keys:),
        expires_in: PROFILE_RESOLUTION_COALESCE_WINDOW
      )
    end

    def should_enqueue_visit_projection?(previous_profile_id:)
      write_coalesced_enqueue_marker(
        visit_projection_cache_key(previous_profile_id:),
        expires_in: VISIT_PROJECTION_COALESCE_WINDOW
      )
    end

    def write_coalesced_enqueue_marker(cache_key, expires_in:)
      if cache_available_for_enqueue_markers?
        Rails.cache.write(cache_key, true, unless_exist: true, expires_in:)
      else
        write_process_local_enqueue_marker(cache_key, expires_in:)
      end
    rescue StandardError
      true
    end

    def cache_available_for_enqueue_markers?
      !Rails.cache.is_a?(ActiveSupport::Cache::NullStore)
    rescue StandardError
      false
    end

    def write_process_local_enqueue_marker(cache_key, expires_in:)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expires_at = now + expires_in.to_f

      ENQUEUE_MARKERS_MUTEX.synchronize do
        ENQUEUE_MARKERS.delete_if { |_key, stored_expires_at| stored_expires_at <= now }

        if ENQUEUE_MARKERS[cache_key].to_f > now
          false
        else
          ENQUEUE_MARKERS[cache_key] = expires_at
          true
        end
      end
    end

    def profile_resolution_cache_key(browser_id:, strong_keys:)
      normalized_keys = strong_keys.to_h.deep_stringify_keys.sort.to_h
      digest = Digest::SHA256.hexdigest(
        {
          browser_id: browser_id.to_s,
          strong_keys: normalized_keys
        }.to_json
      )

      [ "analytics", "visit", id, "profile-resolution", digest ].join(":")
    end

    def visit_projection_cache_key(previous_profile_id:)
      [ "analytics", "visit", id, "visit-projection", analytics_profile_id || "none", previous_profile_id || "none" ].join(":")
    end

    def assign_analytics_site_scope
      self.analytics_site ||= ::Analytics::Current.site_or_default
      self.analytics_site_boundary ||= ::Analytics::Current.site_boundary_or_default if analytics_site.present?
    end
end
