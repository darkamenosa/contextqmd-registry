class CreateAnalyticsSiteLocationHourlyVisitorRollups < ActiveRecord::Migration[8.1]
  def change
    create_table :analytics_site_location_hourly_visitor_rollups do |t|
      t.references :analytics_site, null: false, foreign_key: true
      t.datetime :bucket_start, null: false
      t.string :dimension, null: false
      t.string :value, null: false, default: ""
      t.string :country_code, null: false, default: ""
      t.string :visitor_token, null: false

      t.timestamps
    end

    add_index(
      :analytics_site_location_hourly_visitor_rollups,
      [ :analytics_site_id, :bucket_start, :dimension, :value, :country_code, :visitor_token ],
      unique: true,
      name: "idx_site_location_hourly_rollups_unique"
    )
  end
end
