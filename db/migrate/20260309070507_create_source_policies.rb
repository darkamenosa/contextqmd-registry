class CreateSourcePolicies < ActiveRecord::Migration[8.1]
  def change
    create_table :source_policies do |t|
      t.references :library, null: false, foreign_key: true, index: { unique: true }
      t.string :license_name
      t.string :license_url
      t.string :license_status, null: false, default: "unclear"
      t.boolean :mirror_allowed, default: false
      t.boolean :origin_fetch_allowed, default: true
      t.boolean :attribution_required, default: false
      t.text :notes

      t.timestamps
    end
  end
end
