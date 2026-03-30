# frozen_string_literal: true

class CreateAnalyticsGoogleSearchConsoleConnections < ActiveRecord::Migration[8.0]
  def change
    create_table :analytics_google_search_console_connections do |t|
      t.references :analytics_site, null: false, foreign_key: true
      t.string :google_uid
      t.string :google_email, null: false
      t.text :access_token, null: false
      t.text :refresh_token, null: false
      t.datetime :expires_at
      t.string :property_identifier
      t.string :property_type
      t.string :permission_level
      t.string :status, null: false, default: "active"
      t.boolean :active, null: false, default: true
      t.datetime :connected_at
      t.datetime :disconnected_at
      t.datetime :last_verified_at
      t.jsonb :scopes, null: false, default: []
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :analytics_google_search_console_connections,
      :google_uid
    add_index :analytics_google_search_console_connections,
      [ :analytics_site_id, :active ],
      unique: true,
      where: "\"active\" = TRUE",
      name: "idx_analytics_gsc_connections_on_site_active"
    add_index :analytics_google_search_console_connections,
      [ :analytics_site_id, :property_identifier ],
      name: "idx_analytics_gsc_connections_on_site_property"
  end
end
