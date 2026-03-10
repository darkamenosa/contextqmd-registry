class MakeFetchRecipesVersionIdUnique < ActiveRecord::Migration[8.1]
  def change
    remove_index :fetch_recipes, :version_id
    add_index :fetch_recipes, :version_id, unique: true
  end
end
