# frozen_string_literal: true

class Analytics::GoogleSearchConsoleConnection < AnalyticsRecord
  self.table_name = "analytics_google_search_console_connections"

  STATUS_ACTIVE = "active"
  STATUS_DISCONNECTED = "disconnected"
  STATUS_REVOKED = "revoked"
  STATUS_ERROR = "error"

  belongs_to :analytics_site, class_name: "Analytics::Site", inverse_of: :google_search_console_connections
  has_many :syncs,
    class_name: "Analytics::GoogleSearchConsole::Sync",
    foreign_key: :analytics_google_search_console_connection_id,
    dependent: :delete_all,
    inverse_of: :connection

  encrypts :access_token, :refresh_token

  validates :analytics_site, presence: true
  validates :google_email, presence: true
  validates :status, presence: true

  scope :active, -> { where(active: true) }
  scope :for_analytics_site, ->(site = ::Analytics::Current.site) { site.present? ? where(analytics_site_id: site.id) : none }

  class << self
    def current_for(site = ::Analytics::Current.site)
      return if site.blank?

      active.find_by(analytics_site_id: site.id)
    end

    def configured?(site = ::Analytics::Current.site)
      current_for(site)&.configured? || false
    end

    def rotate_for_site!(site:, attributes:)
      transaction do
        deactivate_active_for_site!(site)

        create!(
          {
            analytics_site: site,
            active: true,
            status: STATUS_ACTIVE,
            connected_at: Time.current,
            metadata: {},
            scopes: [],
            property_identifier: nil,
            property_type: nil,
            permission_level: nil,
            last_verified_at: nil,
            disconnected_at: nil
          }.merge(attributes)
        )
      end
    end

    def deactivate_active_for_site!(site, status: STATUS_DISCONNECTED)
      return if site.blank?

      active.where(analytics_site_id: site.id).update_all(
        active: false,
        status: status,
        disconnected_at: Time.current,
        updated_at: Time.current
      )
    end
  end

  def configured?
    active? && property_identifier.present?
  end

  def property_selected?
    property_identifier.present?
  end

  def disconnect!
    transaction do
      clear_cached_query_rows!

      update!(
        active: false,
        status: STATUS_DISCONNECTED,
        disconnected_at: Time.current
      )
    end
  end

  def store_property!(property)
    next_identifier = property.fetch(:identifier)
    should_clear_cache = property_identifier.present? && property_identifier != next_identifier

    transaction do
      clear_cached_query_rows! if should_clear_cache

      update!(
        property_identifier: next_identifier,
        property_type: property.fetch(:type),
        permission_level: property.fetch(:permission_level),
        last_verified_at: Time.current
      )
    end
  end

  def active_access_token!(client:)
    return access_token if expires_at.blank? || expires_at > 1.minute.from_now

    refreshed = client.refresh_access_token!(refresh_token)
    update!(
      access_token: refreshed.fetch("access_token"),
      expires_at: refreshed["expires_in"].present? ? refreshed["expires_in"].to_i.seconds.from_now : expires_at,
      scopes: normalize_scopes(refreshed["scope"])
    )

    access_token
  end

  private
    def clear_cached_query_rows!
      Analytics::GoogleSearchConsole::QueryRow.for_site(analytics_site).delete_all
    end

    def normalize_scopes(scope_value)
      Array(scope_value.to_s.split(/\s+/).map(&:strip).reject(&:blank?)).uniq
    end
end
