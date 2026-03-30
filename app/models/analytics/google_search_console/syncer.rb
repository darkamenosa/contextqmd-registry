# frozen_string_literal: true

class Analytics::GoogleSearchConsole::Syncer
  DEFAULT_SEARCH_TYPE = "web"
  DEFAULT_RANGE_DAYS = 90
  REFRESH_RANGE_DAYS = 14
  ROW_LIMIT = 25_000
  INSERT_SLICE = 1_000

  class << self
    def ensure_covered!(connection:, from_date:, to_date:, client: nil, search_type: DEFAULT_SEARCH_TYPE)
      return if connection.blank? || connection.property_identifier.blank?

      normalized_from = from_date.to_date
      normalized_to = to_date.to_date
      return if normalized_to < normalized_from

      sync = Analytics::GoogleSearchConsole::Sync.claim_for(
        connection: connection,
        from_date: normalized_from,
        to_date: normalized_to,
        search_type: search_type
      )
      return if sync.blank?

      new(
        connection: connection,
        from_date: normalized_from,
        to_date: normalized_to,
        client: client,
        search_type: search_type,
        sync: sync
      ).perform!
    end

    def default_sync_window
      today = Time.zone.today
      [ (today - DEFAULT_RANGE_DAYS.days), (today - 3.days) ]
    end

    def refresh_sync_window(now: Time.current)
      target_end = now.to_date - 3.days
      [ (target_end - REFRESH_RANGE_DAYS.days), target_end ]
    end
  end

  def initialize(connection:, from_date:, to_date:, client: nil, search_type: DEFAULT_SEARCH_TYPE, sync: nil)
    @connection = connection
    @from_date = from_date.to_date
    @to_date = to_date.to_date
    @client = client || Analytics::GoogleSearchConsole::Client.new
    @search_type = search_type.to_s.presence || DEFAULT_SEARCH_TYPE
    @sync = sync
  end

  def perform!
    raise Analytics::GoogleSearchConsole::Client::Error, "Select a verified Search Console property." if connection.property_identifier.blank?

    sync = @sync || Analytics::GoogleSearchConsole::Sync.claim_for(
      connection: connection,
      from_date: from_date,
      to_date: to_date,
      search_type: search_type
    )
    return if sync.blank?

    rows = collect_rows(sync)

    Analytics::GoogleSearchConsole::QueryRow.transaction do
      Analytics::GoogleSearchConsole::QueryRow
        .for_site(connection.analytics_site)
        .for_search_type(search_type)
        .within_dates(from_date, to_date)
        .delete_all

      rows.each_slice(INSERT_SLICE) do |slice|
        Analytics::GoogleSearchConsole::QueryRow.insert_all!(slice) if slice.any?
      end

      sync.update!(
        finished_at: Time.current,
        status: Analytics::GoogleSearchConsole::Sync::STATUS_SUCCEEDED,
        error_message: nil
      )
    end

    sync
  rescue StandardError => e
    sync&.update!(
      finished_at: Time.current,
      status: Analytics::GoogleSearchConsole::Sync::STATUS_FAILED,
      error_message: e.message.to_s.truncate(1_000)
    )
    raise
  end

  private
    attr_reader :connection, :from_date, :to_date, :client, :search_type

    def collect_rows(sync)
      token = connection.active_access_token!(client: client)
      aggregated_rows = {}
      timestamp = Time.current

      from_date.upto(to_date) do |date|
        start_row = 0

        loop do
          response = client.query_search_analytics(
            token,
            property_identifier: connection.property_identifier,
            start_date: date,
            end_date: date,
            dimensions: %w[query page country device],
            row_limit: ROW_LIMIT,
            start_row: start_row,
            search_type: search_type
          )

          response_rows = Array(response["rows"])
          break if response_rows.empty?

          response_rows.each do |row|
            normalized = normalize_row(row, date:, sync:, timestamp:)
            next if normalized.blank?

            grain = [
              normalized[:analytics_site_id],
              normalized[:date],
              normalized[:search_type],
              normalized[:query],
              normalized[:page],
              normalized[:country],
              normalized[:device]
            ]

            existing = aggregated_rows[grain]
            if existing
              existing[:clicks] += normalized[:clicks]
              existing[:impressions] += normalized[:impressions]
              existing[:position_impressions_sum] += normalized[:position_impressions_sum]
              existing[:updated_at] = timestamp
            else
              aggregated_rows[grain] = normalized
            end
          end

          break if response_rows.length < ROW_LIMIT

          start_row += ROW_LIMIT
        end
      end

      aggregated_rows.values
    end

    def normalize_row(row, date:, sync:, timestamp:)
      keys = Array(row["keys"])
      query_value = keys[0].to_s.strip
      return if query_value.blank?

      impressions = row["impressions"].to_i
      page_value = keys[1].to_s.strip

      {
        analytics_site_id: connection.analytics_site_id,
        analytics_google_search_console_sync_id: sync.id,
        date: date,
        search_type: search_type,
        query: query_value,
        page: Analytics::GoogleSearchConsole::QueryRow.normalize_page_value(page_value),
        country: keys[2].to_s.strip.upcase,
        device: keys[3].to_s.strip.downcase,
        clicks: row["clicks"].to_i,
        impressions: impressions,
        position_impressions_sum: (row["position"].to_f * impressions),
        created_at: timestamp,
        updated_at: timestamp
      }
    end
end
