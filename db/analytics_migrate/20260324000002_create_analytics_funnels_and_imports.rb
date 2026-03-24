class CreateAnalyticsFunnelsAndImports < ActiveRecord::Migration[8.0]
  def change
    create_table :analytics_funnels do |t|
      t.string  :name, null: false
      t.jsonb   :steps, null: false, default: []
      t.integer :created_by_id
      t.timestamps
    end

    add_index :analytics_funnels, :name, unique: true

    create_table :analytics_settings do |t|
      t.string :key, null: false
      t.text   :value
      t.timestamps
    end
    add_index :analytics_settings, :key, unique: true

    # imported_pages, imported_entry_pages, imported_exit_pages removed —
    # dropped in 20260324000004_drop_imported_tables.rb
  end
end
