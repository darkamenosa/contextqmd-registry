class AddStatusToBundles < ActiveRecord::Migration[8.1]
  def change
    add_column :bundles, :status, :string, null: false, default: "ready"
    add_column :bundles, :error_message, :text
  end
end
