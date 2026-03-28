# frozen_string_literal: true

class AddHotFieldsToAnalyticsProfileSummaries < ActiveRecord::Migration[8.0]
  def up
    change_table :analytics_profile_summaries, bulk: true do |t|
      t.string :display_name
      t.string :email
      t.string :latest_country_name
      t.string :latest_country_code
      t.string :latest_region
      t.string :latest_city
      t.string :latest_source
      t.string :latest_browser
      t.string :latest_os
      t.string :latest_device_type
      t.string :latest_current_page
      t.text :search_text
    end
  end

  def down
    change_table :analytics_profile_summaries, bulk: true do |t|
      t.remove :display_name
      t.remove :email
      t.remove :latest_country_name
      t.remove :latest_country_code
      t.remove :latest_region
      t.remove :latest_city
      t.remove :latest_source
      t.remove :latest_browser
      t.remove :latest_os
      t.remove :latest_device_type
      t.remove :latest_current_page
      t.remove :search_text
    end
  end
end
