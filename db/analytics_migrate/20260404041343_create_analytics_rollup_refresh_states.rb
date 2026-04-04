class CreateAnalyticsRollupRefreshStates < ActiveRecord::Migration[8.1]
  def change
    create_table :analytics_rollup_refresh_states do |t|
      t.references :analytics_site, null: false, foreign_key: true, index: false
      t.datetime :bucket_start, null: false
      t.string :rollup_key, null: false
      t.bigint :request_version, null: false, default: 0
      t.bigint :processed_version, null: false, default: 0
      t.datetime :enqueued_at
      t.datetime :processed_at

      t.timestamps
    end

    add_index :analytics_rollup_refresh_states,
      [ :analytics_site_id, :bucket_start, :rollup_key ],
      unique: true,
      name: "idx_analytics_rollup_refresh_states_on_scope"
  end
end
