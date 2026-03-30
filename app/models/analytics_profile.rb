# frozen_string_literal: true

class AnalyticsProfile < AnalyticsRecord
  include AnalyticsProfile::Querying

  RESOLVER_VERSION = 1
  BROWSER_CONTINUITY_WINDOW = 30.days

  STATUS_ANONYMOUS = "anonymous"
  STATUS_IDENTIFIED = "identified"
  STATUS_MERGED = "merged"

  has_many :profile_keys, class_name: "AnalyticsProfileKey", dependent: :destroy
  has_many :visits, class_name: "Ahoy::Visit", foreign_key: :analytics_profile_id, dependent: :nullify
  has_one :summary, class_name: "AnalyticsProfileSummary", dependent: :destroy
  has_many :sessions, class_name: "AnalyticsProfileSession", dependent: :destroy
  belongs_to :analytics_site, class_name: "Analytics::Site", optional: true

  belongs_to :merged_into, class_name: "AnalyticsProfile", optional: true
  has_many :merged_profiles, class_name: "AnalyticsProfile", foreign_key: :merged_into_id, dependent: :nullify

  before_validation :assign_public_id, on: :create
  before_validation :assign_seen_timestamps, on: :create

  validates :public_id, presence: true
  validates :status, presence: true
  validates :first_seen_at, presence: true
  validates :last_seen_at, presence: true

  scope :canonical, -> { where(merged_into_id: nil) }
  scope :anonymous, -> { canonical.where(status: STATUS_ANONYMOUS) }
  scope :for_analytics_site, ->(site = ::Analytics::Current.site) { Analytics::Scope.apply(all, site:) }

  def self.available?
    connection.data_source_exists?(table_name)
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
    false
  end

  def self.resolution_available?
    AnalyticsProfile::Resolution.available?
  end

  def self.resolve_for_visit!(visit:, browser_id:, strong_keys:, occurred_at: nil, identity_snapshot: nil)
    AnalyticsProfile::Resolution.resolve(
      visit: visit,
      browser_id: browser_id,
      strong_keys: strong_keys,
      occurred_at: occurred_at,
      identity_snapshot: identity_snapshot
    )
  end

  def rebuild_projection_later
    Analytics::ProfileProjectionJob.perform_later(self)
  end

  def rebuild_projection_now
    AnalyticsProfile::Projection.rebuild(self)
  end

  def rebuild_summary_later
    Analytics::ProfileSummaryRefreshJob.perform_later(self)
  end

  def rebuild_summary_now
    AnalyticsProfile::Projection.refresh_summary(self)
  end

  def anonymous?
    status == STATUS_ANONYMOUS
  end

  def merge_profile!(other)
    return self if other.blank? || other == self || other.merged_into_id.present?

    transaction do
      return self if analytics_site_id.present? && other.analytics_site_id.present? && analytics_site_id != other.analytics_site_id

      update!(analytics_site_id: other.analytics_site_id) if analytics_site_id.blank? && other.analytics_site_id.present?
      move_keys_from!(other)
      Ahoy::Visit.where(analytics_profile_id: other.id).update_all(analytics_profile_id: id)

      merged_first_seen_at = [ first_seen_at, other.first_seen_at ].compact.min
      merged_last_seen_at = [ last_seen_at, other.last_seen_at ].compact.max
      merged_last_event_at = [ last_event_at, other.last_event_at ].compact.max

      update!(
        first_seen_at: merged_first_seen_at,
        last_seen_at: merged_last_seen_at,
        last_event_at: merged_last_event_at
      )

      other.update!(
        merged_into: self,
        status: STATUS_MERGED,
        last_seen_at: merged_last_seen_at,
        last_event_at: merged_last_event_at
      )

      AnalyticsProfile::Projection.merge_profiles!(from_profile_id: other.id, to_profile_id: id)
    end

    self
  end

  def attach_strong_keys!(strong_keys, observed_at:, identity_snapshot: nil)
    identity_traits = normalized_identity_traits(identity_snapshot)

    strong_keys.each do |key|
      profile_key = profile_keys.find_or_initialize_by(kind: key[:kind], value: key[:value])
      profile_key.source ||= "analytics_resolver"
      profile_key.verified = true if profile_key.respond_to?(:verified=)
      profile_key.first_seen_at ||= observed_at
      profile_key.last_seen_at = [ profile_key.last_seen_at, observed_at ].compact.max
      profile_key.save! if profile_key.new_record? || profile_key.changed?
    end

    return if strong_keys.empty? && identity_traits.empty?

    updates = {
      resolver_version: RESOLVER_VERSION,
      last_seen_at: [ last_seen_at, observed_at ].compact.max
    }
    updates[:analytics_site_id] = analytics_site_id || ::Analytics::Current.site&.id
    updates[:status] = STATUS_IDENTIFIED if strong_keys.any?

    merged_traits = traits.to_h.merge(identity_traits)
    updates[:traits] = merged_traits if merged_traits != traits.to_h

    update!(updates)
  end

  def record_visit!(visit, browser_id:, observed_at:)
    updates = {}
    updates[:analytics_profile_id] = id if visit.has_attribute?(:analytics_profile_id) && visit.analytics_profile_id != id
    if browser_id.present? && visit.has_attribute?(:browser_id) && visit.browser_id != browser_id
      updates[:browser_id] = browser_id
    end

    if updates.present?
      visit.update_columns(updates)
      visit.assign_attributes(updates)
    end

    first_seen = [ first_seen_at, visit.started_at, observed_at ].compact.min
    last_seen = [ last_seen_at, visit.started_at, observed_at ].compact.max
    event_seen = [ last_event_at, observed_at ].compact.max

    update!(
      analytics_site_id: analytics_site_id || visit.analytics_site_id,
      first_seen_at: first_seen,
      last_seen_at: last_seen,
      last_event_at: event_seen,
    resolver_version: RESOLVER_VERSION
  )
  end

  private
    def assign_public_id
      self.public_id ||= SecureRandom.uuid
    end

    def assign_seen_timestamps
      now = Time.current
      self.first_seen_at ||= now
      self.last_seen_at ||= self.first_seen_at || now
      self.resolver_version ||= RESOLVER_VERSION
    end

    def move_keys_from!(other)
      other.profile_keys.find_each do |key|
        existing = profile_keys.find_or_initialize_by(kind: key.kind, value: key.value, analytics_site_id: analytics_site_id)
        existing.source ||= key.source
        existing.verified ||= key.verified
        existing.first_seen_at ||= key.first_seen_at
        existing.last_seen_at = [ existing.last_seen_at, key.last_seen_at ].compact.max
        existing.metadata = key.metadata if existing.metadata.blank? && key.metadata.present?
        existing.save! if existing.new_record? || existing.changed?
      end

      other.profile_keys.delete_all
    end

    def normalized_identity_traits(identity_snapshot)
      return {} if identity_snapshot.blank?

      snapshot = identity_snapshot.to_h.symbolize_keys
      {}.tap do |traits|
        display_name = snapshot[:display_name].presence
        traits["display_name"] = display_name if display_name.present?

        email = snapshot[:email].presence
        traits["email"] = email if email.present?
      end
    end
end
