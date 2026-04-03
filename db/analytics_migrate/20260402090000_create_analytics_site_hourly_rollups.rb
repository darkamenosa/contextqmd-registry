# frozen_string_literal: true

class CreateAnalyticsSiteHourlyRollups < ActiveRecord::Migration[8.1]
  def change
    create_table :analytics_site_visit_hourly_rollups do |t|
      t.references :analytics_site, null: false, foreign_key: true
      t.datetime :bucket_start, null: false
      t.integer :visits_count, null: false, default: 0
      t.integer :unique_visitors_count, null: false, default: 0

      t.timestamps
    end

    add_index :analytics_site_visit_hourly_rollups,
      [ :analytics_site_id, :bucket_start ],
      unique: true,
      name: "idx_site_visit_hourly_rollups_on_site_bucket"
    add_index :analytics_site_visit_hourly_rollups, :bucket_start

    create_table :analytics_site_event_hourly_rollups do |t|
      t.references :analytics_site, null: false, foreign_key: true
      t.datetime :bucket_start, null: false
      t.integer :events_count, null: false, default: 0
      t.integer :pageviews_count, null: false, default: 0

      t.timestamps
    end

    add_index :analytics_site_event_hourly_rollups,
      [ :analytics_site_id, :bucket_start ],
      unique: true,
      name: "idx_site_event_hourly_rollups_on_site_bucket"
    add_index :analytics_site_event_hourly_rollups, :bucket_start
  end
end
