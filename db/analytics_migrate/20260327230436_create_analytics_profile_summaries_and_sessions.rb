class CreateAnalyticsProfileSummariesAndSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :analytics_profile_summaries do |t|
      t.references :analytics_profile, null: false, foreign_key: true
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :last_event_at
      t.bigint :latest_visit_id
      t.integer :total_visits, null: false, default: 0
      t.integer :total_sessions, null: false, default: 0
      t.integer :total_pageviews, null: false, default: 0
      t.integer :total_events, null: false, default: 0
      t.jsonb :latest_context, null: false, default: {}
      t.jsonb :devices_used, null: false, default: []
      t.jsonb :browsers_used, null: false, default: []
      t.jsonb :oses_used, null: false, default: []
      t.jsonb :sources_used, null: false, default: []
      t.jsonb :locations_used, null: false, default: []
      t.jsonb :top_pages, null: false, default: []
      t.timestamps
    end

    remove_index :analytics_profile_summaries, :analytics_profile_id
    add_index :analytics_profile_summaries, :analytics_profile_id, unique: true
    add_foreign_key :analytics_profile_summaries, :ahoy_visits, column: :latest_visit_id

    create_table :analytics_profile_sessions do |t|
      t.references :analytics_profile, null: false, foreign_key: true
      t.references :visit, null: false, foreign_key: { to_table: :ahoy_visits }
      t.datetime :started_at, null: false
      t.datetime :last_event_at
      t.string :country
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
  end
end
