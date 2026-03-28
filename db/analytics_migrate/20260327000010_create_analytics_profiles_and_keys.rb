class CreateAnalyticsProfilesAndKeys < ActiveRecord::Migration[8.0]
  def change
    create_table :analytics_profiles do |t|
      t.string :public_id, null: false
      t.string :status, null: false, default: "anonymous"
      t.references :merged_into, foreign_key: { to_table: :analytics_profiles }
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :last_event_at
      t.jsonb :traits, null: false, default: {}
      t.jsonb :stats, null: false, default: {}
      t.integer :resolver_version, null: false, default: 1
      t.timestamps
    end

    add_index :analytics_profiles, :public_id, unique: true
    add_index :analytics_profiles, :status
    add_index :analytics_profiles, :last_seen_at

    create_table :analytics_profile_keys do |t|
      t.references :analytics_profile, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :value, null: false
      t.string :source
      t.boolean :verified, null: false, default: false
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :analytics_profile_keys, [ :kind, :value ], unique: true
    add_index :analytics_profile_keys, :kind
  end
end
