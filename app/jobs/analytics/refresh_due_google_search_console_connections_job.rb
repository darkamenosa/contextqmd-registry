# frozen_string_literal: true

module Analytics
  class RefreshDueGoogleSearchConsoleConnectionsJob < ApplicationJob
    queue_as :default

    BATCH_SIZE = 100
    MAX_BATCHES = 10

    def perform(now = Time.current)
      from_date, to_date = Analytics::GoogleSearchConsole::Syncer.refresh_sync_window(now: now)
      return if to_date < from_date

      scope = Analytics::GoogleSearchConsoleConnection.active.where.not(property_identifier: [ nil, "" ]).order(:id)

      MAX_BATCHES.times do |batch_index|
        batch = scope.limit(BATCH_SIZE).offset(batch_index * BATCH_SIZE).to_a
        break if batch.empty?

        batch.each do |connection|
          next unless due_for_refresh?(connection, from_date:, to_date:, now:)

          Analytics::GoogleSearchConsoleSyncJob.perform_later(
            connection.id,
            from_date: from_date.iso8601,
            to_date: to_date.iso8601
          )
        end
      end
    end

    private
      def due_for_refresh?(connection, from_date:, to_date:, now:)
        return false if Analytics::GoogleSearchConsole::Sync.running_covering?(
          connection: connection,
          from_date: from_date,
          to_date: to_date,
          search_type: Analytics::GoogleSearchConsole::Syncer::DEFAULT_SEARCH_TYPE,
          now: now
        )

        !Analytics::GoogleSearchConsole::Sync.successful_covering?(
          connection: connection,
          from_date: from_date,
          to_date: to_date,
          search_type: Analytics::GoogleSearchConsole::Syncer::DEFAULT_SEARCH_TYPE
        )
      end
  end
end
