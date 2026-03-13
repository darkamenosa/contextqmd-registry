class AddAccountToActiveStorageTables < ActiveRecord::Migration[8.1]
  def change
    add_reference :active_storage_blobs, :account, foreign_key: true
    add_reference :active_storage_attachments, :account, foreign_key: true
    add_reference :active_storage_variant_records, :account, foreign_key: true
  end
end
