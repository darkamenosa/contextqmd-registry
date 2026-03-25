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

ActiveRecord::Schema[8.1].define(version: 2026_03_25_000009) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "ahoy_events", force: :cascade do |t|
    t.string "name"
    t.jsonb "properties"
    t.datetime "time"
    t.bigint "user_id"
    t.bigint "visit_id"
    t.index "lower((properties ->> 'page'::text))", name: "index_ahoy_events_on_lower_page"
    t.index ["name", "time"], name: "index_ahoy_events_on_name_and_time"
    t.index ["properties"], name: "index_ahoy_events_on_properties", opclass: :jsonb_path_ops, using: :gin
    t.index ["time", "visit_id"], name: "index_ahoy_events_on_time_and_visit_id"
    t.index ["user_id"], name: "index_ahoy_events_on_user_id"
    t.index ["visit_id"], name: "index_ahoy_events_on_visit_id"
  end

  create_table "ahoy_visits", force: :cascade do |t|
    t.string "app_version"
    t.string "browser"
    t.string "browser_version"
    t.string "city"
    t.string "country"
    t.string "device_type"
    t.string "hostname"
    t.string "ip"
    t.text "landing_page"
    t.float "latitude"
    t.float "longitude"
    t.string "os"
    t.string "os_version"
    t.string "platform"
    t.text "referrer"
    t.string "referring_domain"
    t.string "region"
    t.string "screen_size"
    t.string "source_channel"
    t.string "source_favicon_domain"
    t.string "source_kind"
    t.string "source_label"
    t.string "source_match_strategy"
    t.boolean "source_paid", default: false, null: false
    t.string "source_rule_id"
    t.integer "source_rule_version"
    t.datetime "started_at"
    t.text "user_agent"
    t.bigint "user_id"
    t.string "utm_campaign"
    t.string "utm_content"
    t.string "utm_medium"
    t.string "utm_source"
    t.string "utm_term"
    t.string "visit_token"
    t.string "visitor_token"
    t.index ["latitude", "longitude"], name: "index_ahoy_visits_on_coordinates", where: "((latitude IS NOT NULL) AND (longitude IS NOT NULL))"
    t.index ["source_channel", "started_at"], name: "index_ahoy_visits_on_source_channel_and_started_at"
    t.index ["source_channel"], name: "index_ahoy_visits_on_source_channel"
    t.index ["source_kind"], name: "index_ahoy_visits_on_source_kind"
    t.index ["source_label", "started_at"], name: "index_ahoy_visits_on_source_label_and_started_at"
    t.index ["source_label"], name: "index_ahoy_visits_on_source_label"
    t.index ["started_at"], name: "index_ahoy_visits_on_started_at"
    t.index ["user_id"], name: "index_ahoy_visits_on_user_id"
    t.index ["visit_token"], name: "index_ahoy_visits_on_visit_token", unique: true
    t.index ["visitor_token", "started_at"], name: "index_ahoy_visits_on_visitor_token_and_started_at"
  end

  create_table "analytics_funnels", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.string "name", null: false
    t.jsonb "steps", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_analytics_funnels_on_name", unique: true
  end

  create_table "analytics_goals", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.jsonb "custom_props", default: {}, null: false
    t.string "display_name", null: false
    t.string "event_name"
    t.string "page_path"
    t.integer "scroll_threshold", default: -1, null: false
    t.datetime "updated_at", null: false
    t.index ["display_name"], name: "index_analytics_goals_on_display_name", unique: true
    t.index ["event_name", "custom_props"], name: "index_analytics_goals_on_event_name_and_custom_props", unique: true, where: "(event_name IS NOT NULL)"
    t.index ["page_path", "scroll_threshold"], name: "index_analytics_goals_on_page_path_and_scroll_threshold", unique: true, where: "(page_path IS NOT NULL)"
  end

  create_table "analytics_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["key"], name: "index_analytics_settings_on_key", unique: true
  end
end
