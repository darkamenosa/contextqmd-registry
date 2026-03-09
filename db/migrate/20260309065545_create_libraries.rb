class CreateLibraries < ActiveRecord::Migration[8.1]
  def change
    create_table :libraries do |t|
      t.references :account, null: false, foreign_key: true
      t.string :namespace, null: false
      t.string :name, null: false
      t.string :display_name, null: false
      t.jsonb :aliases, default: []
      t.string :homepage_url
      t.string :default_version

      t.timestamps
    end

    add_index :libraries, %i[namespace name], unique: true
    add_index :libraries, :aliases, using: :gin
  end
end
