class RelaxGoalEventNameUniqueness < ActiveRecord::Migration[8.0]
  def change
    remove_index :analytics_goals,
      name: "index_analytics_goals_on_event_name"

    add_index :analytics_goals, [ :event_name, :custom_props ],
      unique: true,
      where: "event_name IS NOT NULL"
  end
end
