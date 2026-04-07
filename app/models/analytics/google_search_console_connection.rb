# frozen_string_literal: true

class Analytics::GoogleSearchConsoleConnection < AnalyticsRecord
  self.table_name = "analytics_google_search_console_connections"

  STATUS_ACTIVE = "active"
  STATUS_DISCONNECTED = "disconnected"
  STATUS_REVOKED = "revoked"
  STATUS_ERROR = "error"
  VERIFIED_PROPERTIES_METADATA_KEY = "verified_properties"
  PROPERTIES_REFRESHED_AT_METADATA_KEY = "verified_properties_refreshed_at"
  PROPERTIES_ERROR_METADATA_KEY = "verified_properties_error"
  CONNECTION_ERROR_METADATA_KEY = "connection_error"
  CONNECTION_ERROR_AT_METADATA_KEY = "connection_error_at"

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

  def reauth_required?
    status == STATUS_REVOKED
  end

  def connection_error_message
    metadata[CONNECTION_ERROR_METADATA_KEY].presence
  end

  def properties_refresh_error
    metadata[PROPERTIES_ERROR_METADATA_KEY].presence
  end

  def properties_refreshed_at
    parse_metadata_time(metadata[PROPERTIES_REFRESHED_AT_METADATA_KEY])
  end

  def cached_properties
    Array(metadata[VERIFIED_PROPERTIES_METADATA_KEY]).filter_map do |property|
      normalize_property(property)
    end
  end

  def cached_property(identifier)
    cached_properties.find { |property| property.fetch(:identifier) == identifier.to_s }
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

  def cache_verified_properties!(properties, fetched_at: Time.current)
    normalized_properties = Array(properties).filter_map { |property| normalize_property(property) }
    current_property_present = normalized_properties.any? do |property|
      property.fetch(:identifier) == property_identifier.to_s
    end

    update!(
      status: STATUS_ACTIVE,
      last_verified_at: current_property_present ? fetched_at : last_verified_at,
      metadata: metadata.merge(
        VERIFIED_PROPERTIES_METADATA_KEY => normalized_properties.map(&:stringify_keys),
        PROPERTIES_REFRESHED_AT_METADATA_KEY => fetched_at.iso8601,
        PROPERTIES_ERROR_METADATA_KEY => nil,
        CONNECTION_ERROR_METADATA_KEY => nil,
        CONNECTION_ERROR_AT_METADATA_KEY => nil
      )
    )
  end

  def refresh_verified_properties_later
    Analytics::GoogleSearchConsolePropertiesRefreshJob.perform_later(id)
  end

  def refresh_verified_properties_now(client: Analytics::GoogleSearchConsole::Client.new)
    token = active_access_token!(client: client)
    properties = client.list_verified_properties(token)

    cache_verified_properties!(properties)
  rescue Analytics::GoogleSearchConsole::Client::Error => e
    mark_reauth_required!(e.message) if e.reauth_required?
    mark_properties_refresh_failed!(e.message) unless e.reauth_required?
    raise
  end

  def store_property!(property)
    normalized_property = normalize_property(property)
    next_identifier = normalized_property.fetch(:identifier)
    should_clear_cache = property_identifier.present? && property_identifier != next_identifier

    transaction do
      clear_cached_query_rows! if should_clear_cache

      update!(
        property_identifier: next_identifier,
        property_type: normalized_property.fetch(:type),
        permission_level: normalized_property.fetch(:permission_level),
        last_verified_at: Time.current
      )
    end
  end

  def active_access_token!(client:)
    if reauth_required?
      raise Analytics::GoogleSearchConsole::Client::Error.new(
        connection_error_message || "Reconnect Google Search Console to continue.",
        reason: :reauth_required
      )
    end

    return access_token if expires_at.blank? || expires_at > 1.minute.from_now

    refreshed = client.refresh_access_token!(refresh_token)
    update!(
      access_token: refreshed.fetch("access_token"),
      expires_at: refreshed["expires_in"].present? ? refreshed["expires_in"].to_i.seconds.from_now : expires_at,
      scopes: normalize_scopes(refreshed["scope"]),
      status: STATUS_ACTIVE,
      metadata: metadata.merge(
        CONNECTION_ERROR_METADATA_KEY => nil,
        CONNECTION_ERROR_AT_METADATA_KEY => nil
      )
    )

    access_token
  rescue Analytics::GoogleSearchConsole::Client::Error => e
    mark_reauth_required!(e.message) if e.reauth_required?
    raise
  end

  private
    def mark_reauth_required!(message, at: Time.current)
      update!(
        status: STATUS_REVOKED,
        metadata: metadata.merge(
          CONNECTION_ERROR_METADATA_KEY => message,
          CONNECTION_ERROR_AT_METADATA_KEY => at.iso8601
        )
      )
    end

    def mark_properties_refresh_failed!(message)
      update!(
        metadata: metadata.merge(
          PROPERTIES_ERROR_METADATA_KEY => message
        )
      )
    end

    def clear_cached_query_rows!
      Analytics::GoogleSearchConsole::QueryRow.for_site(analytics_site).delete_all
    end

    def normalize_scopes(scope_value)
      Array(scope_value.to_s.split(/\s+/).map(&:strip).reject(&:blank?)).uniq
    end

    def normalize_property(property)
      candidate = property.respond_to?(:with_indifferent_access) ? property.with_indifferent_access : property
      identifier = candidate[:identifier].to_s.strip
      return if identifier.blank?

      {
        identifier: identifier,
        type: candidate[:type].to_s,
        permission_level: candidate[:permission_level].to_s,
        label: candidate[:label].to_s
      }
    end

    def parse_metadata_time(value)
      return if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end
end
