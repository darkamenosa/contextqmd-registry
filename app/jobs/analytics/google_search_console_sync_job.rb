# frozen_string_literal: true

module Analytics
  class GoogleSearchConsoleSyncJob < ApplicationJob
    queue_as :default

    def perform(connection_id, from_date:, to_date:, search_type: Analytics::GoogleSearchConsole::Syncer::DEFAULT_SEARCH_TYPE)
      connection = Analytics::GoogleSearchConsoleConnection.find_by(id: connection_id)
      return if connection.blank? || !connection.active? || connection.property_identifier.blank?

      Analytics::GoogleSearchConsole::Syncer.ensure_covered!(
        connection: connection,
        from_date: Date.parse(from_date.to_s),
        to_date: Date.parse(to_date.to_s),
        search_type: search_type
      )
    end
  end
end
