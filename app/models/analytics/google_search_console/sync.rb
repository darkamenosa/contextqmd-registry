# frozen_string_literal: true

class Analytics::GoogleSearchConsole::Sync < AnalyticsRecord
  self.table_name = "analytics_google_search_console_syncs"

  STATUS_RUNNING = "running"
  STATUS_SUCCEEDED = "succeeded"
  STATUS_FAILED = "failed"
  RUNNING_TIMEOUT = 2.hours

  belongs_to :connection,
    class_name: "Analytics::GoogleSearchConsoleConnection",
    foreign_key: :analytics_google_search_console_connection_id,
    inverse_of: :syncs
  has_many :query_rows,
    class_name: "Analytics::GoogleSearchConsole::QueryRow",
    foreign_key: :analytics_google_search_console_sync_id,
    dependent: :delete_all,
    inverse_of: :sync

  validates :connection, :property_identifier, :search_type, :from_date, :to_date, :started_at, :status, presence: true

  scope :successful, -> { where(status: STATUS_SUCCEEDED) }
  scope :running, -> { where(status: STATUS_RUNNING) }
  scope :latest_first, -> { order(Arel.sql("COALESCE(finished_at, started_at) DESC"), id: :desc) }

  class << self
    def latest_for(connection)
      return if connection.blank?

      where(
        analytics_google_search_console_connection_id: connection.id,
        property_identifier: connection.property_identifier.to_s
      ).latest_first.first
    end

    def successful_covering?(connection:, from_date:, to_date:, search_type:)
      return false if connection.blank? || connection.property_identifier.blank?

      successful
        .where(
          analytics_google_search_console_connection_id: connection.id,
          property_identifier: connection.property_identifier.to_s,
          search_type: search_type
        )
        .where("from_date <= ? AND to_date >= ?", from_date, to_date)
        .exists?
    end

    def running_covering?(connection:, from_date:, to_date:, search_type:, now: Time.current)
      return false if connection.blank? || connection.property_identifier.blank?

      running
        .where(
          analytics_google_search_console_connection_id: connection.id,
          property_identifier: connection.property_identifier.to_s,
          search_type: search_type
        )
        .where("from_date <= ? AND to_date >= ?", from_date, to_date)
        .where("started_at >= ?", now - RUNNING_TIMEOUT)
        .exists?
    end

    def claim_for(connection:, from_date:, to_date:, search_type:)
      return if connection.blank? || connection.property_identifier.blank?

      connection.with_lock do
        connection.reload
        next if successful_covering?(connection:, from_date:, to_date:, search_type:)
        next if running_covering?(connection:, from_date:, to_date:, search_type:)

        connection.syncs.create!(
          property_identifier: connection.property_identifier,
          search_type: search_type,
          from_date: from_date,
          to_date: to_date,
          started_at: Time.current,
          status: STATUS_RUNNING
        )
      end
    end
  end
end
