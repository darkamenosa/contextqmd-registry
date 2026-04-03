# frozen_string_literal: true

class RefactorAnalyticsVisitSummariesAndDropProfileSessions < ActiveRecord::Migration[8.1]
  def up
    rename_table :analytics_visit_page_summaries, :analytics_visit_summaries
    rename_index :analytics_visit_summaries, "idx_visit_page_summaries_entry_lookup", "idx_visit_summaries_entry_lookup"
    rename_index :analytics_visit_summaries, "idx_visit_page_summaries_exit_lookup", "idx_visit_summaries_exit_lookup"
    remove_foreign_key :analytics_visit_summaries, column: :visit_id
    add_foreign_key :analytics_visit_summaries, :ahoy_visits, column: :visit_id, on_delete: :cascade
    remove_foreign_key :analytics_visit_page_engagements, column: :visit_id
    add_foreign_key :analytics_visit_page_engagements, :ahoy_visits, column: :visit_id, on_delete: :cascade

    change_table :analytics_visit_summaries, bulk: true do |t|
      t.references :analytics_profile, foreign_key: true
      t.string :country
      t.string :country_code
      t.string :region
      t.string :city
      t.string :device_type
      t.string :os
      t.string :browser
      t.string :source
      t.string :current_page
      t.integer :duration_seconds, null: false, default: 0
    end

    add_index :analytics_visit_summaries, [ :analytics_profile_id, :started_at ], name: "index_visit_summaries_on_profile_id_and_started_at"
    add_index :analytics_visit_summaries, [ :analytics_profile_id, :last_event_at ], name: "index_visit_summaries_on_profile_id_and_last_event_at"
    add_check_constraint :analytics_visit_summaries, "country_code IS NULL OR country_code ~ '^[A-Z]{2}$'", name: "analytics_visit_summaries_country_code_format"

    execute <<~SQL.squish
      UPDATE analytics_visit_summaries
      SET analytics_profile_id = analytics_profile_sessions.analytics_profile_id,
          country = analytics_profile_sessions.country,
          country_code = analytics_profile_sessions.country_code,
          region = analytics_profile_sessions.region,
          city = analytics_profile_sessions.city,
          device_type = analytics_profile_sessions.device_type,
          os = analytics_profile_sessions.os,
          browser = analytics_profile_sessions.browser,
          source = analytics_profile_sessions.source,
          current_page = analytics_profile_sessions.current_page,
          duration_seconds = analytics_profile_sessions.duration_seconds,
          last_event_at = COALESCE(analytics_profile_sessions.last_event_at, analytics_visit_summaries.last_event_at),
          events_count = COALESCE(analytics_visit_summaries.events_count, analytics_profile_sessions.events_count),
          engaged_ms_total = COALESCE(analytics_visit_summaries.engaged_ms_total, analytics_profile_sessions.engaged_ms_total),
          event_names = COALESCE(analytics_visit_summaries.event_names, analytics_profile_sessions.event_names),
          page_paths = COALESCE(analytics_visit_summaries.page_paths, analytics_profile_sessions.page_paths)
      FROM analytics_profile_sessions
      WHERE analytics_visit_summaries.visit_id = analytics_profile_sessions.visit_id
    SQL

    drop_table :analytics_profile_sessions
  end

  def down
    create_table :analytics_profile_sessions do |t|
      t.references :analytics_profile, null: false, foreign_key: true
      t.references :analytics_site, foreign_key: true
      t.references :visit, null: false, foreign_key: { to_table: :ahoy_visits }
      t.datetime :started_at, null: false
      t.datetime :last_event_at
      t.string :country
      t.string :country_code
      t.string :region
      t.string :city
      t.string :device_type
      t.string :os
      t.string :browser
      t.string :source
      t.string :entry_page
      t.string :exit_page
      t.string :current_page
      t.integer :duration_seconds, null: false, default: 0
      t.integer :engaged_ms_total, null: false, default: 0
      t.integer :pageviews_count, null: false, default: 0
      t.integer :events_count, null: false, default: 0
      t.jsonb :page_paths, null: false, default: []
      t.jsonb :event_names, null: false, default: []
      t.timestamps
    end

    remove_index :analytics_profile_sessions, :visit_id
    add_index :analytics_profile_sessions, :visit_id, unique: true
    add_index :analytics_profile_sessions, [ :analytics_profile_id, :started_at ], name: "index_profile_sessions_on_profile_id_and_started_at"
    add_index :analytics_profile_sessions, [ :analytics_profile_id, :last_event_at ], name: "index_profile_sessions_on_profile_id_and_last_event_at"
    add_check_constraint :analytics_profile_sessions, "country_code IS NULL OR country_code ~ '^[A-Z]{2}$'", name: "analytics_profile_sessions_country_code_format"

    execute <<~SQL.squish
      INSERT INTO analytics_profile_sessions (
        analytics_profile_id,
        analytics_site_id,
        visit_id,
        started_at,
        last_event_at,
        country,
        country_code,
        region,
        city,
        device_type,
        os,
        browser,
        source,
        entry_page,
        exit_page,
        current_page,
        duration_seconds,
        engaged_ms_total,
        pageviews_count,
        events_count,
        page_paths,
        event_names,
        created_at,
        updated_at
      )
      SELECT analytics_profile_id,
             analytics_site_id,
             visit_id,
             started_at,
             last_event_at,
             country,
             country_code,
             region,
             city,
             device_type,
             os,
             browser,
             source,
             entry_page,
             exit_page,
             current_page,
             duration_seconds,
             COALESCE(engaged_ms_total, 0),
             pageviews_count,
             COALESCE(events_count, 0),
             COALESCE(page_paths, '[]'::jsonb),
             COALESCE(event_names, '[]'::jsonb),
             created_at,
             updated_at
      FROM analytics_visit_summaries
      WHERE analytics_profile_id IS NOT NULL
    SQL

    remove_index :analytics_visit_summaries, name: "index_visit_summaries_on_profile_id_and_last_event_at"
    remove_index :analytics_visit_summaries, name: "index_visit_summaries_on_profile_id_and_started_at"
    remove_check_constraint :analytics_visit_summaries, name: "analytics_visit_summaries_country_code_format"
    remove_reference :analytics_visit_summaries, :analytics_profile, foreign_key: true
    remove_foreign_key :analytics_visit_page_engagements, column: :visit_id
    add_foreign_key :analytics_visit_page_engagements, :ahoy_visits, column: :visit_id
    remove_foreign_key :analytics_visit_summaries, column: :visit_id
    add_foreign_key :analytics_visit_summaries, :ahoy_visits, column: :visit_id

    change_table :analytics_visit_summaries, bulk: true do |t|
      t.remove :country
      t.remove :country_code
      t.remove :region
      t.remove :city
      t.remove :device_type
      t.remove :os
      t.remove :browser
      t.remove :source
      t.remove :current_page
      t.remove :duration_seconds
    end

    rename_index :analytics_visit_summaries, "idx_visit_summaries_entry_lookup", "idx_visit_page_summaries_entry_lookup"
    rename_index :analytics_visit_summaries, "idx_visit_summaries_exit_lookup", "idx_visit_page_summaries_exit_lookup"
    rename_table :analytics_visit_summaries, :analytics_visit_page_summaries
  end
end
