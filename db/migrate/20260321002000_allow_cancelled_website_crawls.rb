# frozen_string_literal: true

class AllowCancelledWebsiteCrawls < ActiveRecord::Migration[8.1]
  def change
    remove_check_constraint :website_crawls, name: "website_crawls_status_check"

    add_check_constraint :website_crawls,
      "status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')",
      name: "website_crawls_status_check"
  end
end
