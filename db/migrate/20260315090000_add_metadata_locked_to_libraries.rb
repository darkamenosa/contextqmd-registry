# frozen_string_literal: true

class AddMetadataLockedToLibraries < ActiveRecord::Migration[8.0]
  def change
    add_column :libraries, :metadata_locked, :boolean, default: false, null: false
  end
end
