class AddCountryCodeToAnalyticsLocationTables < ActiveRecord::Migration[8.0]
  def up
    add_column :ahoy_visits, :country_code, :string
    add_column :analytics_profile_sessions, :country_code, :string
    add_index :ahoy_visits, :country_code
    add_index :analytics_profile_sessions, :country_code
  end

  def down
    remove_index :analytics_profile_sessions, :country_code
    remove_index :ahoy_visits, :country_code
    remove_column :analytics_profile_sessions, :country_code
    remove_column :ahoy_visits, :country_code
  end
end
