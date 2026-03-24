class AddLiveQueryIndexes < ActiveRecord::Migration[8.0]
  def change
    add_index :ahoy_events, [ :time, :visit_id ], name: "index_ahoy_events_on_time_and_visit_id"
  end
end
