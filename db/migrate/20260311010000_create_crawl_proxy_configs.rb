# frozen_string_literal: true

class CreateCrawlProxyConfigs < ActiveRecord::Migration[8.1]
  def change
    create_table :crawl_proxy_configs do |t|
      t.string :name, null: false
      t.string :scheme, null: false, default: "http"  # http, https, socks5
      t.string :host, null: false
      t.integer :port, null: false
      t.string :username
      t.string :password
      t.string :provider                               # e.g. "brightdata", "oxylabs"
      t.string :kind, default: "datacenter"            # datacenter, residential, mobile
      t.boolean :active, null: false, default: true
      t.integer :priority, null: false, default: 0     # higher = preferred
      t.string :usage_scope, default: "all"            # website, structured, all
      t.boolean :supports_sticky_sessions, default: false
      t.datetime :cooldown_until
      t.integer :consecutive_failures, default: 0
      t.datetime :last_success_at
      t.datetime :last_failure_at
      t.string :last_error_class
      t.string :last_target_host
      t.text :notes
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :crawl_proxy_configs, :active
    add_index :crawl_proxy_configs, [ :active, :usage_scope ]
    add_index :crawl_proxy_configs, :cooldown_until
  end
end
