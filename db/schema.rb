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

ActiveRecord::Schema[8.1].define(version: 2026_03_09_052642) do
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

  add_foreign_key "access_tokens", "identities"
  add_foreign_key "account_cancellations", "accounts", on_delete: :cascade
  add_foreign_key "account_cancellations", "users", column: "initiated_by_id", on_delete: :nullify
  add_foreign_key "users", "accounts"
  add_foreign_key "users", "identities", on_delete: :nullify
end
