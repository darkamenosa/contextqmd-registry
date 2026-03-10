class CreateVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :versions do |t|
      t.references :library, null: false, foreign_key: true
      t.string :version, null: false
      t.string :channel, null: false
      t.datetime :generated_at
      t.string :source_url
      t.string :source_etag
      t.string :source_last_modified
      t.string :manifest_checksum

      t.timestamps
    end

    add_index :versions, %i[library_id version], unique: true
  end
end
