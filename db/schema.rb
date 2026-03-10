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

ActiveRecord::Schema[8.1].define(version: 2026_03_11_030001) do
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

  create_table "bundles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "format"
    t.string "profile"
    t.string "sha256"
    t.bigint "size_bytes"
    t.datetime "updated_at", null: false
    t.string "url"
    t.bigint "version_id", null: false
    t.index ["version_id", "profile"], name: "index_bundles_on_version_id_and_profile", unique: true
    t.index ["version_id"], name: "index_bundles_on_version_id"
  end

  create_table "crawl_proxy_configs", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "consecutive_failures", default: 0
    t.datetime "cooldown_until"
    t.datetime "created_at", null: false
    t.string "host", null: false
    t.string "kind", default: "datacenter"
    t.string "last_error_class"
    t.datetime "last_failure_at"
    t.datetime "last_success_at"
    t.string "last_target_host"
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
  end

  create_table "crawl_requests", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.bigint "identity_id", null: false
    t.bigint "library_id"
    t.jsonb "metadata", default: {}
    t.string "source_type", default: "website", null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.string "status_message"
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["identity_id"], name: "index_crawl_requests_on_identity_id"
    t.index ["library_id"], name: "index_crawl_requests_on_library_id"
    t.index ["status"], name: "index_crawl_requests_on_status"
  end

  create_table "fetch_recipes", force: :cascade do |t|
    t.jsonb "allowed_hosts"
    t.jsonb "content_types"
    t.datetime "created_at", null: false
    t.bigint "max_bytes"
    t.string "normalizer_version"
    t.text "signature"
    t.string "source_type"
    t.string "splitter_version"
    t.datetime "updated_at", null: false
    t.string "url"
    t.bigint "version_id", null: false
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
    t.string "name", null: false
    t.string "namespace", null: false
    t.string "source_type"
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_libraries_on_account_id"
    t.index ["aliases"], name: "index_libraries_on_aliases", using: :gin
    t.index ["namespace", "name"], name: "index_libraries_on_namespace_and_name", unique: true
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
    t.string "source_url"
    t.datetime "updated_at", null: false
    t.string "version"
    t.index ["library_id", "version"], name: "index_versions_on_library_id_and_version", unique: true
    t.index ["library_id"], name: "index_versions_on_library_id"
  end

  add_foreign_key "access_tokens", "identities"
  add_foreign_key "account_cancellations", "accounts", on_delete: :cascade
  add_foreign_key "account_cancellations", "users", column: "initiated_by_id", on_delete: :nullify
  add_foreign_key "bundles", "versions"
  add_foreign_key "crawl_requests", "identities"
  add_foreign_key "crawl_requests", "libraries"
  add_foreign_key "fetch_recipes", "versions"
  add_foreign_key "libraries", "accounts"
  add_foreign_key "pages", "versions"
  add_foreign_key "source_policies", "libraries"
  add_foreign_key "users", "accounts"
  add_foreign_key "users", "identities", on_delete: :nullify
  add_foreign_key "versions", "libraries"
end
