# frozen_string_literal: true

class AlignCrawlSchemaWithArchitecture < ActiveRecord::Migration[8.1]
  def change
    # Contract columns for crawl lifecycle (stale detection, duration, user-facing progress)
    change_table :crawl_requests, bulk: true do |t|
      t.datetime :started_at
      t.datetime :completed_at
      t.string :status_message
    end

    # Git re-crawl change detection (compare HEAD SHA to skip unchanged repos)
    add_column :versions, :last_crawl_sha, :string

    # Obsoleted by git clone approach (no more REST API conditional requests)
    remove_column :versions, :source_etag, :string
    remove_column :versions, :source_last_modified, :string
    remove_column :fetch_recipes, :expected_etag, :string
    remove_column :fetch_recipes, :expected_last_modified, :string
  end
end
