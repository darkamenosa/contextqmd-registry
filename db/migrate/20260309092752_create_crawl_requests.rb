class CreateCrawlRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :crawl_requests do |t|
      t.references :identity, null: false, foreign_key: true
      t.string :url, null: false
      t.string :source_type, null: false, default: "website"
      t.string :status, null: false, default: "pending"
      t.references :library, null: true, foreign_key: true
      t.text :error_message
      t.jsonb :metadata, default: {}

      t.timestamps
    end
    add_index :crawl_requests, :status
  end
end
