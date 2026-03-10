class CreateBundles < ActiveRecord::Migration[8.1]
  def change
    create_table :bundles do |t|
      t.references :version, null: false, foreign_key: true
      t.string :profile, null: false
      t.string :format, null: false
      t.string :sha256, null: false
      t.bigint :size_bytes
      t.string :url

      t.timestamps
    end

    add_index :bundles, %i[version_id profile], unique: true
  end
end
