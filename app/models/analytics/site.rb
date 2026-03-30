# frozen_string_literal: true

class Analytics::Site < AnalyticsRecord
  self.table_name = "analytics_sites"

  STATUS_ACTIVE = "active"
  STATUS_ARCHIVED = "archived"

  has_many :boundaries,
    class_name: "Analytics::SiteBoundary",
    foreign_key: :analytics_site_id,
    dependent: :destroy,
    inverse_of: :site
  has_many :google_search_console_connections,
    class_name: "Analytics::GoogleSearchConsoleConnection",
    foreign_key: :analytics_site_id,
    dependent: :destroy,
    inverse_of: :analytics_site
  has_many :google_search_console_query_rows,
    class_name: "Analytics::GoogleSearchConsole::QueryRow",
    foreign_key: :analytics_site_id,
    dependent: :delete_all,
    inverse_of: :analytics_site
  has_many :analytics_profiles,
    class_name: "AnalyticsProfile",
    foreign_key: :analytics_site_id,
    dependent: :nullify,
    inverse_of: :analytics_site
  has_many :allowed_event_properties,
    class_name: "Analytics::AllowedEventProperty",
    foreign_key: :analytics_site_id,
    dependent: :delete_all,
    inverse_of: :analytics_site

  before_validation :assign_public_id, on: :create
  before_validation :normalize_fields
  after_commit :sync_primary_boundary!, on: [ :create, :update ]

  validates :public_id, presence: true, uniqueness: true
  validates :name, presence: true
  validates :status, presence: true

  scope :active, -> { where(status: STATUS_ACTIVE) }

  class << self
    def sole_active
      sites = active.order(:id).limit(2).to_a
      sites.one? ? sites.first : nil
    end
  end

  private
    def assign_public_id
      self.public_id ||= SecureRandom.uuid
    end

    def normalize_fields
      self.name = name.to_s.strip.presence
      self.canonical_hostname = Analytics::SiteBoundary.normalize_host(canonical_hostname)
      self.time_zone = time_zone.to_s.strip.presence
      self.status = status.to_s.strip.presence || STATUS_ACTIVE
      self.metadata = metadata.to_h if metadata.respond_to?(:to_h)
      self.metadata ||= {}
    end

    def sync_primary_boundary!
      return if canonical_hostname.blank?

      boundary = boundaries.find_or_initialize_by(primary: true)
      boundary.host = canonical_hostname
      boundary.path_prefix = "/"
      boundary.priority = 0 if boundary.priority.blank?
      boundary.primary = true
      boundary.save! if boundary.new_record? || boundary.changed?
    end
end
