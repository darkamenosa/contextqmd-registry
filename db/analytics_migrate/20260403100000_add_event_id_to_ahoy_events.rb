# frozen_string_literal: true

class AddEventIdToAhoyEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :ahoy_events, :event_id, :string
    add_index :ahoy_events, :event_id, unique: true, where: "event_id IS NOT NULL"
  end
end
