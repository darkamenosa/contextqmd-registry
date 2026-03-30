# frozen_string_literal: true

class CreateAnalyticsGoogleSearchConsoleSyncsAndQueryRows < ActiveRecord::Migration[8.0]
  def change
    create_table :analytics_google_search_console_syncs do |t|
      t.references :analytics_google_search_console_connection, null: false, foreign_key: true, index: { name: "idx_analytics_gsc_syncs_on_connection_id" }
      t.string :property_identifier, null: false
      t.string :search_type, null: false, default: "web"
      t.date :from_date, null: false
      t.date :to_date, null: false
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.string :status, null: false, default: "running"
      t.text :error_message
      t.timestamps
    end

    add_index :analytics_google_search_console_syncs,
      [ :analytics_google_search_console_connection_id, :property_identifier, :search_type, :from_date, :to_date ],
      name: "idx_analytics_gsc_syncs_on_connection_property_range"
    add_index :analytics_google_search_console_syncs,
      [ :status, :finished_at ],
      name: "idx_analytics_gsc_syncs_on_status_finished_at"

    create_table :analytics_google_search_console_query_rows do |t|
      t.references :analytics_site, null: false, foreign_key: true
      t.references :analytics_google_search_console_sync, null: false, foreign_key: true, index: { name: "idx_analytics_gsc_query_rows_on_sync_id" }
      t.date :date, null: false
      t.string :search_type, null: false, default: "web"
      t.text :query, null: false
      t.text :page, null: false, default: ""
      t.string :country, null: false, default: ""
      t.string :device, null: false, default: ""
      t.integer :clicks, null: false, default: 0
      t.integer :impressions, null: false, default: 0
      t.decimal :position_impressions_sum, null: false, default: 0, precision: 18, scale: 6
      t.timestamps
    end

    add_index :analytics_google_search_console_query_rows,
      [ :analytics_site_id, :date ],
      name: "idx_analytics_gsc_query_rows_on_site_date"
    add_index :analytics_google_search_console_query_rows,
      [ :analytics_site_id, :date, :search_type, :country ],
      name: "idx_analytics_gsc_query_rows_on_site_date_type_country"
    add_index :analytics_google_search_console_query_rows,
      [ :analytics_site_id, :date, :search_type, :query, :page, :country, :device ],
      unique: true,
      name: "idx_analytics_gsc_query_rows_on_site_grain"
  end
end
