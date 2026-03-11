# frozen_string_literal: true

class UpgradeProxyPoolForLeases < ActiveRecord::Migration[8.1]
  def change
    add_column :crawl_proxy_configs, :bypass, :string
    add_column :crawl_proxy_configs, :disabled_reason, :string
    add_column :crawl_proxy_configs, :max_concurrency, :integer, null: false, default: 4
    add_column :crawl_proxy_configs, :lease_ttl_seconds, :integer, null: false, default: 900
    add_column :crawl_proxy_configs, :last_http_status, :integer

    add_index :crawl_proxy_configs, %i[scheme host port username], unique: true, name: "index_crawl_proxy_configs_on_identity"

    create_table :crawl_proxy_leases do |t|
      t.references :crawl_proxy_config, null: false, foreign_key: true
      t.string :usage_scope, null: false, default: "all"
      t.string :session_key, null: false
      t.string :target_host
      t.boolean :sticky_session, null: false, default: false
      t.datetime :last_seen_at, null: false
      t.datetime :expires_at, null: false
      t.datetime :released_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :crawl_proxy_leases, :expires_at
    add_index :crawl_proxy_leases, %i[crawl_proxy_config_id released_at expires_at], name: "index_crawl_proxy_leases_on_proxy_and_state"
    add_index :crawl_proxy_leases, %i[usage_scope session_key], unique: true, where: "released_at IS NULL", name: "index_crawl_proxy_leases_on_scope_and_session_key"
  end
end
