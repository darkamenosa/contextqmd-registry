# frozen_string_literal: true

class NormalizePagesInAnalyticsGoogleSearchConsoleQueryRows < ActiveRecord::Migration[8.0]
  NORMALIZED_PAGE_SQL = <<~SQL.squish.freeze
    COALESCE(
      NULLIF(
        regexp_replace(split_part(page, '?', 1), '^https?://[^/]+', ''),
        ''
      ),
      '/'
    )
  SQL

  def up
    execute <<~SQL.squish
      CREATE TEMP TABLE analytics_google_search_console_query_rows_canonical AS
      SELECT
        analytics_site_id,
        MIN(analytics_google_search_console_sync_id) AS analytics_google_search_console_sync_id,
        date,
        search_type,
        query,
        #{NORMALIZED_PAGE_SQL} AS page,
        country,
        device,
        SUM(clicks) AS clicks,
        SUM(impressions) AS impressions,
        SUM(position_impressions_sum) AS position_impressions_sum,
        MIN(created_at) AS created_at,
        MAX(updated_at) AS updated_at
      FROM analytics_google_search_console_query_rows
      GROUP BY
        analytics_site_id,
        date,
        search_type,
        query,
        #{NORMALIZED_PAGE_SQL},
        country,
        device
    SQL

    execute "DELETE FROM analytics_google_search_console_query_rows"

    execute <<~SQL.squish
      INSERT INTO analytics_google_search_console_query_rows (
        analytics_site_id,
        analytics_google_search_console_sync_id,
        date,
        search_type,
        query,
        page,
        country,
        device,
        clicks,
        impressions,
        position_impressions_sum,
        created_at,
        updated_at
      )
      SELECT
        analytics_site_id,
        analytics_google_search_console_sync_id,
        date,
        search_type,
        query,
        page,
        country,
        device,
        clicks,
        impressions,
        position_impressions_sum,
        created_at,
        updated_at
      FROM analytics_google_search_console_query_rows_canonical
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Canonical page normalization merges duplicate cached fact rows."
  end
end
