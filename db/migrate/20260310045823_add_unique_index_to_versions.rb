class AddUniqueIndexToVersions < ActiveRecord::Migration[8.1]
  def change
    add_index :versions, [ :library_id, :version ], unique: true
  end
end
