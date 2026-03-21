# frozen_string_literal: true

class AddWebsiteCrawlCounters < ActiveRecord::Migration[8.1]
  def change
    add_column :website_crawls, :discovered_urls_count, :integer, null: false, default: 0
    add_column :website_crawls, :processed_urls_count, :integer, null: false, default: 0
  end
end
