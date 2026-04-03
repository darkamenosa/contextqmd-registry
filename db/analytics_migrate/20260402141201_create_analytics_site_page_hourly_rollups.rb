class CreateAnalyticsSitePageHourlyRollups < ActiveRecord::Migration[8.1]
  def change
    create_table :analytics_site_page_hourly_rollups do |t|
      t.references :analytics_site, null: false, foreign_key: true
      t.datetime :bucket_start, null: false
      t.string :page_path, null: false, default: ""
      t.string :visitor_token, null: false
      t.integer :pageviews_count, null: false, default: 0

      t.timestamps
    end

    add_index(
      :analytics_site_page_hourly_rollups,
      [ :analytics_site_id, :bucket_start, :page_path, :visitor_token ],
      unique: true,
      name: "idx_site_page_hourly_rollups_unique"
    )
  end
end
