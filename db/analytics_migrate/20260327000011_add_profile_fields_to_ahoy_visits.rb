class AddProfileFieldsToAhoyVisits < ActiveRecord::Migration[8.0]
  def change
    add_reference :ahoy_visits, :analytics_profile, foreign_key: true
    add_column :ahoy_visits, :browser_id, :string

    add_index :ahoy_visits, [ :browser_id, :started_at ]
  end
end
