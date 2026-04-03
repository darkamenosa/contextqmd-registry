class CreateAnalyticsVisitPageEngagements < ActiveRecord::Migration[8.1]
  def change
    create_table :analytics_visit_page_engagements do |t|
      t.references :analytics_site, null: false, foreign_key: true
      t.references :visit, null: false, foreign_key: { to_table: :ahoy_visits, on_delete: :cascade }
      t.datetime :started_at, null: false
      t.string :visitor_token, null: false
      t.text :page_path, null: false, default: ""
      t.integer :pageviews_count, null: false, default: 0
      t.float :legacy_time_on_page_seconds, null: false, default: 0.0
      t.integer :legacy_time_on_page_count, null: false, default: 0
      t.float :engaged_seconds_total, null: false, default: 0.0
      t.boolean :has_engagement, null: false, default: false
      t.float :max_scroll_depth, null: false, default: 0.0

      t.timestamps
    end

    add_index(
      :analytics_visit_page_engagements,
      [ :visit_id, :page_path ],
      unique: true,
      name: "idx_analytics_visit_page_engagements_on_visit_page"
    )
    add_index(
      :analytics_visit_page_engagements,
      [ :analytics_site_id, :started_at, :page_path ],
      name: "idx_analytics_visit_page_engagements_lookup"
    )
  end
end
