class CreateAnalyticsGoals < ActiveRecord::Migration[8.0]
  def change
    create_table :analytics_goals do |t|
      t.string :display_name, null: false
      t.string :event_name
      t.string :page_path
      t.integer :scroll_threshold, null: false, default: -1
      t.jsonb :custom_props, null: false, default: {}
      t.integer :created_by_id
      t.timestamps
    end

    add_index :analytics_goals, :display_name, unique: true
    add_index :analytics_goals, :event_name, unique: true, where: "event_name IS NOT NULL"
    add_index :analytics_goals, [ :page_path, :scroll_threshold ],
      unique: true,
      where: "page_path IS NOT NULL"
  end
end
