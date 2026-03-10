class AddMissingUniqueIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :bundles, [:version_id, :profile], unique: true
    remove_index :source_policies, :library_id
    add_index :source_policies, :library_id, unique: true
  end
end
