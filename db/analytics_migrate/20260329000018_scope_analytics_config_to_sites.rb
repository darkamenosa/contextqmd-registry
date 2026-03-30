# frozen_string_literal: true

class ScopeAnalyticsConfigToSites < ActiveRecord::Migration[8.0]
  def up
    add_reference :analytics_settings, :analytics_site, foreign_key: true
    add_reference :analytics_goals, :analytics_site, foreign_key: true
    add_reference :analytics_funnels, :analytics_site, foreign_key: true

    remove_index :analytics_settings, :key
    add_index :analytics_settings, "COALESCE(analytics_site_id, 0), key", unique: true, name: "index_analytics_settings_on_site_scope_and_key"

    remove_index :analytics_goals, :display_name
    remove_index :analytics_goals, name: "index_analytics_goals_on_event_name_and_custom_props"
    remove_index :analytics_goals, name: "index_analytics_goals_on_page_path_and_scroll_threshold"
    add_index :analytics_goals, "COALESCE(analytics_site_id, 0), display_name", unique: true, name: "idx_goals_site_scope_display_name"
    add_index :analytics_goals, "COALESCE(analytics_site_id, 0), event_name, custom_props", unique: true, where: "(event_name IS NOT NULL)", name: "idx_goals_site_scope_event_props"
    add_index :analytics_goals, "COALESCE(analytics_site_id, 0), page_path, scroll_threshold", unique: true, where: "(page_path IS NOT NULL)", name: "idx_goals_site_scope_page_scroll"

    remove_index :analytics_funnels, :name
    add_index :analytics_funnels, "COALESCE(analytics_site_id, 0), name", unique: true, name: "idx_funnels_site_scope_name"
  end

  def down
    remove_index :analytics_funnels, name: "idx_funnels_site_scope_name"
    add_index :analytics_funnels, :name, unique: true

    remove_index :analytics_goals, name: "idx_goals_site_scope_page_scroll"
    remove_index :analytics_goals, name: "idx_goals_site_scope_event_props"
    remove_index :analytics_goals, name: "idx_goals_site_scope_display_name"
    add_index :analytics_goals, :display_name, unique: true
    add_index :analytics_goals, [ :event_name, :custom_props ], unique: true, where: "(event_name IS NOT NULL)"
    add_index :analytics_goals, [ :page_path, :scroll_threshold ], unique: true, where: "(page_path IS NOT NULL)"

    remove_index :analytics_settings, name: "index_analytics_settings_on_site_scope_and_key"
    add_index :analytics_settings, :key, unique: true

    remove_reference :analytics_funnels, :analytics_site, foreign_key: true
    remove_reference :analytics_goals, :analytics_site, foreign_key: true
    remove_reference :analytics_settings, :analytics_site, foreign_key: true
  end
end
