class AddMetricsToAnalyticsVisitPageSummaries < ActiveRecord::Migration[8.1]
  def change
    add_column :analytics_visit_page_summaries, :visit_duration_seconds, :float, null: false, default: 0.0
    add_column :analytics_visit_page_summaries, :has_non_pageview_events, :boolean, null: false, default: false
  end
end
