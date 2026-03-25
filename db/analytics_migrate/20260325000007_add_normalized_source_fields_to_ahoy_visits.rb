class AddNormalizedSourceFieldsToAhoyVisits < ActiveRecord::Migration[8.0]
  def change
    change_table :ahoy_visits, bulk: true do |t|
      t.string :source_label
      t.string :source_kind
      t.string :source_channel
      t.string :source_favicon_domain
      t.boolean :source_paid, null: false, default: false
      t.string :source_rule_id
      t.integer :source_rule_version
      t.string :source_match_strategy
    end

    add_index :ahoy_visits, :source_label
    add_index :ahoy_visits, :source_kind
    add_index :ahoy_visits, :source_channel
  end
end
