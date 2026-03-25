# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_21_003000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "access_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.bigint "identity_id", null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.string "permission", default: "read", null: false
    t.string "token_digest", null: false
    t.string "token_prefix", limit: 8
    t.datetime "updated_at", null: false
    t.index ["identity_id"], name: "index_access_tokens_on_identity_id"
    t.index ["token_digest"], name: "index_access_tokens_on_token_digest", unique: true
  end

  create_table "account_cancellations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.bigint "initiated_by_id"
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_account_cancellations_on_account_id_unique", unique: true
    t.index ["initiated_by_id"], name: "index_account_cancellations_on_initiated_by_id"
  end

  create_table "accounts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigserial "external_account_id", null: false
    t.string "name", null: false
    t.boolean "personal", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["external_account_id"], name: "index_accounts_on_external_account_id", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "account_id"
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["account_id"], name: "index_active_storage_attachments_on_account_id"
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "account_id"
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["account_id"], name: "index_active_storage_blobs_on_account_id"
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "account_id"
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["account_id"], name: "index_active_storage_variant_records_on_account_id"
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "bundles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "format"
    t.string "profile"
    t.string "sha256"
    t.bigint "size_bytes"
    t.string "status", default: "ready", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.bigint "version_id", null: false
    t.string "visibility", default: "public", null: false
    t.index ["version_id", "profile"], name: "index_bundles_on_version_id_and_profile", unique: true
    t.index ["version_id"], name: "index_bundles_on_version_id"
  end

  create_table "crawl_proxy_configs", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "bypass"
    t.integer "consecutive_failures", default: 0
    t.datetime "cooldown_until"
    t.datetime "created_at", null: false
    t.string "disabled_reason"
    t.string "host", null: false
    t.string "kind", default: "datacenter"
    t.string "last_error_class"
    t.datetime "last_failure_at"
    t.integer "last_http_status"
    t.datetime "last_success_at"
    t.string "last_target_host"
    t.integer "lease_ttl_seconds", default: 900, null: false
    t.integer "max_concurrency", default: 4, null: false
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.text "notes"
    t.string "password"
    t.integer "port", null: false
    t.integer "priority", default: 0, null: false
    t.string "provider"
    t.string "scheme", default: "http", null: false
    t.boolean "supports_sticky_sessions", default: false
    t.datetime "updated_at", null: false
    t.string "usage_scope", default: "all"
    t.string "username"
    t.index ["active", "usage_scope"], name: "index_crawl_proxy_configs_on_active_and_usage_scope"
    t.index ["active"], name: "index_crawl_proxy_configs_on_active"
    t.index ["cooldown_until"], name: "index_crawl_proxy_configs_on_cooldown_until"
    t.index ["scheme", "host", "port", "username"], name: "index_crawl_proxy_configs_on_identity", unique: true
  end

  create_table "crawl_proxy_leases", force: :cascade do |t|
    t.bigint "crawl_proxy_config_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_seen_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "released_at"
    t.string "session_key", null: false
    t.boolean "sticky_session", default: false, null: false
    t.string "target_host"
    t.datetime "updated_at", null: false
    t.string "usage_scope", default: "all", null: false
    t.index ["crawl_proxy_config_id", "released_at", "expires_at"], name: "index_crawl_proxy_leases_on_proxy_and_state"
    t.index ["crawl_proxy_config_id"], name: "index_crawl_proxy_leases_on_crawl_proxy_config_id"
    t.index ["expires_at"], name: "index_crawl_proxy_leases_on_expires_at"
    t.index ["usage_scope", "session_key"], name: "index_crawl_proxy_leases_on_scope_and_session_key", unique: true, where: "(released_at IS NULL)"
  end

  create_table "crawl_requests", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "creator_id"
    t.text "error_message"
    t.bigint "library_id"
    t.bigint "library_source_id"
    t.jsonb "metadata", default: {}
    t.string "requested_bundle_visibility", default: "public", null: false
    t.string "source_type", default: "website", null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.string "status_message"
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["creator_id"], name: "index_crawl_requests_on_creator_id"
    t.index ["library_id"], name: "index_crawl_requests_on_library_id"
    t.index ["library_source_id"], name: "index_crawl_requests_on_library_source_id"
    t.index ["status"], name: "index_crawl_requests_on_status"
    t.check_constraint "requested_bundle_visibility::text = ANY (ARRAY['public'::character varying::text, 'private'::character varying::text])", name: "crawl_requests_bundle_visibility_check"
    t.check_constraint "source_type::text = ANY (ARRAY['github'::character varying::text, 'gitlab'::character varying::text, 'bitbucket'::character varying::text, 'git'::character varying::text, 'website'::character varying::text, 'openapi'::character varying::text, 'llms_txt'::character varying::text])", name: "crawl_requests_source_type_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text])", name: "crawl_requests_status_check"
  end

  create_table "fetch_recipes", force: :cascade do |t|
    t.jsonb "allowed_hosts"
    t.jsonb "content_types"
    t.datetime "created_at", null: false
    t.bigint "library_source_id"
    t.bigint "max_bytes"
    t.string "normalizer_version"
    t.text "signature"
    t.string "source_type"
    t.string "splitter_version"
    t.datetime "updated_at", null: false
    t.string "url"
    t.bigint "version_id", null: false
    t.index ["library_source_id"], name: "index_fetch_recipes_on_library_source_id"
    t.index ["version_id"], name: "index_fetch_recipes_on_version_id", unique: true
  end

  create_table "identities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.boolean "password_set_by_user", default: false, null: false
    t.string "provider"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "sign_in_count", default: 0, null: false
    t.boolean "staff", default: false, null: false
    t.datetime "suspended_at"
    t.string "uid"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_identities_on_email", unique: true
    t.index ["provider", "uid"], name: "index_identities_on_provider_and_uid", unique: true
    t.index ["reset_password_token"], name: "index_identities_on_reset_password_token", unique: true
  end

  create_table "libraries", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.jsonb "aliases", default: []
    t.jsonb "crawl_rules", default: {}
    t.datetime "created_at", null: false
    t.string "default_version"
    t.string "display_name", null: false
    t.string "homepage_url"
    t.datetime "latest_version_at"
    t.boolean "metadata_locked", default: false, null: false
    t.string "name", null: false
    t.string "namespace", null: false
    t.string "slug", null: false
    t.string "source_type"
    t.integer "total_pages_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "versions_count", default: 0, null: false
    t.index ["account_id"], name: "index_libraries_on_account_id"
    t.index ["aliases"], name: "index_libraries_on_aliases", using: :gin
    t.index ["namespace", "name"], name: "index_libraries_on_namespace_and_name", unique: true
    t.index ["slug"], name: "index_libraries_on_slug", unique: true
  end

  create_table "library_sources", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "consecutive_no_change_checks", default: 0, null: false
    t.jsonb "crawl_rules", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "last_crawled_at"
    t.string "last_probe_signature"
    t.datetime "last_version_change_at"
    t.datetime "last_version_check_at"
    t.bigint "library_id", null: false
    t.datetime "next_version_check_at"
    t.boolean "primary", default: false, null: false
    t.string "source_type", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.datetime "version_check_claimed_at"
    t.index ["library_id", "primary"], name: "index_library_sources_on_library_id_and_primary", unique: true, where: "(\"primary\" = true)"
    t.index ["library_id"], name: "index_library_sources_on_library_id"
    t.index ["next_version_check_at"], name: "index_library_sources_on_next_version_check_at"
    t.index ["url"], name: "index_library_sources_on_url", unique: true
  end

  create_table "pages", force: :cascade do |t|
    t.integer "bytes"
    t.string "checksum"
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "headings"
    t.string "page_uid"
    t.string "path"
    t.jsonb "previous_paths"
    t.string "source_ref"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "url"
    t.bigint "version_id", null: false
    t.index "(((setweight(to_tsvector('english'::regconfig, (COALESCE(title, ''::character varying))::text), 'A'::\"char\") || setweight(to_tsvector('english'::regconfig, COALESCE(description, ''::text)), 'B'::\"char\")) || setweight(to_tsvector('english'::regconfig, (COALESCE(path, ''::character varying))::text), 'C'::\"char\")))", name: "index_pages_on_search", using: :gin
    t.index ["version_id", "page_uid"], name: "index_pages_on_version_id_and_page_uid", unique: true
    t.index ["version_id"], name: "index_pages_on_version_id"
  end

  create_table "source_policies", force: :cascade do |t|
    t.boolean "attribution_required"
    t.datetime "created_at", null: false
    t.bigint "library_id", null: false
    t.string "license_name"
    t.string "license_status"
    t.string "license_url"
    t.boolean "mirror_allowed"
    t.text "notes"
    t.boolean "origin_fetch_allowed"
    t.datetime "updated_at", null: false
    t.index ["library_id"], name: "index_source_policies_on_library_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.bigint "identity_id"
    t.string "name", null: false
    t.string "role", default: "member", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "role"], name: "index_users_on_account_id_and_role"
    t.index ["account_id"], name: "index_users_on_account_id"
    t.index ["account_id"], name: "index_users_on_account_id_where_owner", unique: true, where: "((role)::text = 'owner'::text)"
    t.index ["account_id"], name: "index_users_on_account_id_where_system", unique: true, where: "((role)::text = 'system'::text)"
    t.index ["identity_id", "account_id"], name: "index_users_on_identity_id_and_account_id", unique: true, where: "(identity_id IS NOT NULL)"
    t.index ["identity_id"], name: "index_users_on_identity_id"
    t.check_constraint "role::text <> 'system'::text OR identity_id IS NULL", name: "users_system_role_requires_no_identity"
  end

  create_table "versions", force: :cascade do |t|
    t.string "channel"
    t.datetime "created_at", null: false
    t.datetime "generated_at"
    t.bigint "library_id", null: false
    t.string "manifest_checksum"
    t.integer "pages_count", default: 0, null: false
    t.string "source_url"
    t.datetime "updated_at", null: false
    t.string "version"
    t.index ["library_id", "version"], name: "index_versions_on_library_id_and_version", unique: true
    t.index ["library_id"], name: "index_versions_on_library_id"
  end

  create_table "website_crawl_pages", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.jsonb "headings", default: [], null: false
    t.string "page_uid", null: false
    t.string "path", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.bigint "website_crawl_id", null: false
    t.bigint "website_crawl_url_id", null: false
    t.index ["website_crawl_id", "id"], name: "index_website_crawl_pages_on_website_crawl_id_and_id"
    t.index ["website_crawl_id"], name: "index_website_crawl_pages_on_website_crawl_id"
    t.index ["website_crawl_url_id"], name: "index_website_crawl_pages_on_website_crawl_url_id", unique: true
  end

  create_table "website_crawl_urls", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "normalized_url", null: false
    t.datetime "processed_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.bigint "website_crawl_id", null: false
    t.index ["website_crawl_id", "normalized_url"], name: "idx_on_website_crawl_id_normalized_url_929719a98d", unique: true
    t.index ["website_crawl_id", "status", "id"], name: "index_website_crawl_urls_on_website_crawl_id_and_status_and_id"
    t.index ["website_crawl_id"], name: "index_website_crawl_urls_on_website_crawl_id"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'fetched'::character varying::text, 'skipped'::character varying::text, 'failed'::character varying::text])", name: "website_crawl_urls_status_check"
  end

  create_table "website_crawls", force: :cascade do |t|
    t.datetime "completed_at"
    t.bigint "crawl_request_id", null: false
    t.datetime "created_at", null: false
    t.integer "discovered_urls_count", default: 0, null: false
    t.text "error_message"
    t.integer "processed_urls_count", default: 0, null: false
    t.string "runner", default: "auto", null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["crawl_request_id"], name: "index_website_crawls_on_crawl_request_id", unique: true
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text])", name: "website_crawls_status_check"
  end

  add_foreign_key "access_tokens", "identities"
  add_foreign_key "account_cancellations", "accounts", on_delete: :cascade
  add_foreign_key "account_cancellations", "users", column: "initiated_by_id", on_delete: :nullify
  add_foreign_key "active_storage_attachments", "accounts"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_blobs", "accounts"
  add_foreign_key "active_storage_variant_records", "accounts"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "bundles", "versions"
  add_foreign_key "crawl_proxy_leases", "crawl_proxy_configs"
  add_foreign_key "crawl_requests", "libraries"
  add_foreign_key "crawl_requests", "library_sources"
  add_foreign_key "crawl_requests", "users", column: "creator_id"
  add_foreign_key "fetch_recipes", "library_sources"
  add_foreign_key "fetch_recipes", "versions"
  add_foreign_key "libraries", "accounts"
  add_foreign_key "library_sources", "libraries"
  add_foreign_key "pages", "versions"
  add_foreign_key "source_policies", "libraries"
  add_foreign_key "users", "accounts"
  add_foreign_key "users", "identities", on_delete: :nullify
  add_foreign_key "versions", "libraries"
  add_foreign_key "website_crawl_pages", "website_crawl_urls"
  add_foreign_key "website_crawl_pages", "website_crawls"
  add_foreign_key "website_crawl_urls", "website_crawls"
  add_foreign_key "website_crawls", "crawl_requests"
end
