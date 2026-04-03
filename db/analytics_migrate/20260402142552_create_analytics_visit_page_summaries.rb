class CreateAnalyticsVisitPageSummaries < ActiveRecord::Migration[8.1]
  def change
    create_table :analytics_visit_page_summaries do |t|
      t.references :visit, null: false, foreign_key: { to_table: :ahoy_visits, on_delete: :cascade }, index: { unique: true }
      t.references :analytics_site, null: false, foreign_key: true
      t.datetime :started_at, null: false
      t.string :visitor_token, null: false
      t.string :entry_page, null: false, default: ""
      t.string :exit_page, null: false, default: ""
      t.integer :pageviews_count, null: false, default: 0

      t.timestamps
    end

    add_index :analytics_visit_page_summaries, [ :analytics_site_id, :started_at, :entry_page ], name: "idx_visit_page_summaries_entry_lookup"
    add_index :analytics_visit_page_summaries, [ :analytics_site_id, :started_at, :exit_page ], name: "idx_visit_page_summaries_exit_lookup"
  end
end
