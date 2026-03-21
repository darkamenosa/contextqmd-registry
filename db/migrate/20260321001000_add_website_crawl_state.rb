# frozen_string_literal: true

class AddWebsiteCrawlState < ActiveRecord::Migration[8.1]
  def change
    add_column :website_crawls, :runner, :string, null: false, default: "auto"

    create_table :website_crawl_urls do |t|
      t.references :website_crawl, null: false, foreign_key: true
      t.string :url, null: false
      t.string :normalized_url, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :processed_at
      t.timestamps
    end

    add_index :website_crawl_urls, [ :website_crawl_id, :normalized_url ], unique: true
    add_index :website_crawl_urls, [ :website_crawl_id, :status, :id ]
    add_check_constraint :website_crawl_urls,
      "status IN ('pending', 'fetched', 'skipped', 'failed')",
      name: "website_crawl_urls_status_check"

    create_table :website_crawl_pages do |t|
      t.references :website_crawl, null: false, foreign_key: true
      t.references :website_crawl_url, null: false, foreign_key: true, index: false
      t.string :page_uid, null: false
      t.string :path, null: false
      t.string :title, null: false
      t.string :url, null: false
      t.text :content, null: false
      t.jsonb :headings, null: false, default: []
      t.timestamps
    end

    add_index :website_crawl_pages, :website_crawl_url_id, unique: true
    add_index :website_crawl_pages, [ :website_crawl_id, :id ]
  end
end
