class AddVisibilityToBundlesAndCrawlRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :bundles, :visibility, :string, null: false, default: "public"
    add_column :crawl_requests, :requested_bundle_visibility, :string, null: false, default: "public"
  end
end
