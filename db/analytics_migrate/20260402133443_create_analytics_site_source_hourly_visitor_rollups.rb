class CreateAnalyticsSiteSourceHourlyVisitorRollups < ActiveRecord::Migration[8.1]
  def change
    create_table :analytics_site_source_hourly_visitor_rollups do |t|
      t.references :analytics_site, index: false, null: false, foreign_key: true
      t.datetime :bucket_start, null: false
      t.string :dimension, null: false
      t.string :value, null: false, default: ""
      t.string :visitor_token, null: false

      t.timestamps

      t.index [ :analytics_site_id, :bucket_start, :dimension, :value, :visitor_token ],
        unique: true,
        name: "idx_site_source_hourly_rollups_unique"
    end
  end
end
