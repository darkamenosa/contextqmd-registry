class AddSourceQueryIndexesToAhoyVisits < ActiveRecord::Migration[8.0]
  def change
    add_index :ahoy_visits, [ :source_label, :started_at ], name: "index_ahoy_visits_on_source_label_and_started_at"
    add_index :ahoy_visits, [ :source_channel, :started_at ], name: "index_ahoy_visits_on_source_channel_and_started_at"
  end
end
