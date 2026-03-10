class CreateFetchRecipes < ActiveRecord::Migration[8.1]
  def change
    create_table :fetch_recipes do |t|
      t.references :version, null: false, foreign_key: true
      t.string :source_type, null: false
      t.string :url, null: false
      t.jsonb :allowed_hosts, default: []
      t.jsonb :content_types, default: []
      t.bigint :max_bytes
      t.string :expected_etag
      t.string :expected_last_modified
      t.string :normalizer_version
      t.string :splitter_version
      t.text :signature

      t.timestamps
    end
  end
end
