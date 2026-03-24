class AddAnalyticsIndexes < ActiveRecord::Migration[8.0]
  def change
    add_index :ahoy_events,
              "LOWER((properties->>'page'))",
              name: "index_ahoy_events_on_lower_page"

    add_index :ahoy_visits,
              [ :latitude, :longitude ],
              where: "latitude IS NOT NULL AND longitude IS NOT NULL",
              name: "index_ahoy_visits_on_coordinates"
  end
end
