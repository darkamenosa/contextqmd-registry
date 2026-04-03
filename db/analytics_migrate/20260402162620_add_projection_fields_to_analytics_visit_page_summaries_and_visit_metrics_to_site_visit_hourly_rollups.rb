# frozen_string_literal: true

class AddProjectionFieldsToAnalyticsVisitPageSummariesAndVisitMetricsToSiteVisitHourlyRollups < ActiveRecord::Migration[8.1]
  def change
    change_table :analytics_visit_page_summaries, bulk: true do |t|
      t.datetime :last_event_at
      t.integer :events_count
      t.integer :engaged_ms_total
      t.jsonb :event_names
      t.jsonb :page_paths
    end

    change_table :analytics_site_visit_hourly_rollups, bulk: true do |t|
      t.integer :pageviews_count
      t.integer :bounces_count
      t.float :total_visit_duration_seconds
    end
  end
end
