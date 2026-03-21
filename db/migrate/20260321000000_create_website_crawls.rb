# frozen_string_literal: true

class CreateWebsiteCrawls < ActiveRecord::Migration[8.1]
  def change
    create_table :website_crawls do |t|
      t.references :crawl_request, null: false, foreign_key: true, index: { unique: true }
      t.string :status, null: false, default: "pending"
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_message
      t.timestamps
    end

    add_check_constraint :website_crawls,
      "status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')",
      name: "website_crawls_status_check"
  end
end
