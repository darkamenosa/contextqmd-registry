class CreatePages < ActiveRecord::Migration[8.1]
  def change
    create_table :pages do |t|
      t.references :version, null: false, foreign_key: true
      t.string :page_uid, null: false
      t.string :path, null: false
      t.string :title, null: false
      t.string :url
      t.text :description
      t.string :checksum
      t.integer :bytes
      t.jsonb :headings, default: []
      t.jsonb :previous_paths, default: []
      t.string :source_ref

      t.timestamps
    end

    add_index :pages, %i[version_id page_uid], unique: true
  end
end
