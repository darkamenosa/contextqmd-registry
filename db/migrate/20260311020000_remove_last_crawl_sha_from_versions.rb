# frozen_string_literal: true

class RemoveLastCrawlShaFromVersions < ActiveRecord::Migration[8.1]
  def change
    remove_column :versions, :last_crawl_sha, :string
  end
end
