class ReplaceCrawlRequestIdentityWithCreator < ActiveRecord::Migration[8.1]
  def change
    add_reference :crawl_requests, :creator, null: true, foreign_key: { to_table: :users }
    remove_reference :crawl_requests, :identity, null: true, foreign_key: true
  end
end
