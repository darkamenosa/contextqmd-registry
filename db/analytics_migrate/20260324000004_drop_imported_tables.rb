class DropImportedTables < ActiveRecord::Migration[8.0]
  def change
    drop_table :imported_pages, if_exists: true
    drop_table :imported_entry_pages, if_exists: true
    drop_table :imported_exit_pages, if_exists: true
  end
end
