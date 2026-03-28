# frozen_string_literal: true

require "test_helper"

class Admin::AnalyticsReportsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  INERTIA_HEADERS = {
    "X-Inertia" => "true",
    "X-Inertia-Version" => ViteRuby.digest,
    "X-Requested-With" => "XMLHttpRequest",
    "ACCEPT" => "text/html, application/xhtml+xml"
  }.freeze

  setup do
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
    AnalyticsProfileSession.delete_all if defined?(AnalyticsProfileSession)
    AnalyticsProfileSummary.delete_all if defined?(AnalyticsProfileSummary)
    AnalyticsSetting.delete_all
    Goal.delete_all
    Funnel.delete_all
  end

  test "reports shell hides behaviors when nothing is configured or discovered" do
    staff_identity, = create_tenant(
      email: "staff-reports-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Reports"
    )
    staff_identity.update!(staff: true)

    sign_in(staff_identity)

    get "/admin/analytics/reports", headers: INERTIA_HEADERS

    assert_response :success

    payload = JSON.parse(response.body)
    site = payload.fetch("props").fetch("site")

    assert_equal false, site.fetch("hasGoals")
    assert_equal false, site.fetch("propsAvailable")
    assert_equal false, site.fetch("funnelsAvailable")
    assert_equal true, site.fetch("flags").fetch("dbip")
  ensure
    Current.reset
  end

  test "reports shell reads behaviors capabilities from stored analytics config" do
    staff_identity, = create_tenant(
      email: "staff-reports-config-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Reports Config"
    )
    staff_identity.update!(staff: true)

    Goal.create!(display_name: "Signup", event_name: "Signup", custom_props: {})
    AnalyticsSetting.set_json("allowed_event_props", [ "plan" ])
    Funnel.create!(name: "Signup funnel", steps: [ { type: "event", value: "Signup" } ])

    sign_in(staff_identity)

    get "/admin/analytics/reports", headers: INERTIA_HEADERS

    assert_response :success

    site = JSON.parse(response.body).fetch("props").fetch("site")
    assert_equal true, site.fetch("hasGoals")
    assert_equal true, site.fetch("propsAvailable")
    assert_equal true, site.fetch("funnelsAvailable")
  ensure
    Current.reset
  end

  test "reports shell can boot visitors mode from analytics profiles" do
    staff_identity, = create_tenant(
      email: "staff-reports-profiles-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Reports Profiles"
    )
    staff_identity.update!(staff: true)

    profile = AnalyticsProfile.create!(
      status: AnalyticsProfile::STATUS_ANONYMOUS,
      traits: { display_name: "coral wildcat" },
      first_seen_at: 30.minutes.ago,
      last_seen_at: 2.minutes.ago
    )

    visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      analytics_profile: profile,
      browser_id: SecureRandom.uuid,
      started_at: 4.minutes.ago.change(usec: 0),
      country: "Sweden",
      city: "Stockholm",
      device_type: "Desktop",
      os: "Mac OS",
      browser: "Safari",
      source_label: "Direct/None",
      landing_page: "https://example.test/"
    )

    Ahoy::Event.create!(
      visit: visit,
      name: "pageview",
      properties: { page: "/" },
      time: 3.minutes.ago.change(usec: 0)
    )

    sign_in(staff_identity)

    get "/admin/analytics/reports",
        params: { behaviors_mode: "visitors" },
        headers: INERTIA_HEADERS

    assert_response :success

    payload = JSON.parse(response.body).fetch("props")
    site = payload.fetch("site")
    boot = payload.fetch("boot")

    assert_equal true, site.fetch("profilesAvailable")
    assert_equal "visitors", boot.fetch("ui").fetch("behaviorsMode")
    assert_equal "profiles", boot.fetch("behaviors").fetch("kind")
    assert_equal "coral wildcat", boot.fetch("behaviors").fetch("results").first.fetch("name")
  ensure
    Current.reset
  end

  test "reports shell defaults match day of week when comparison param is absent" do
    staff_identity, = create_tenant(
      email: "staff-reports-match-weekday-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Reports Match Weekday"
    )
    staff_identity.update!(staff: true)

    sign_in(staff_identity)

    get "/admin/analytics/reports", headers: INERTIA_HEADERS

    assert_response :success

    payload = JSON.parse(response.body).fetch("props")
    query = payload.fetch("query")

    assert_equal true, json_key(query, "matchDayOfWeek", "match_day_of_week")
  ensure
    Current.reset
  end

  test "reports shell marks goals available when custom events exist" do
    staff_identity, = create_tenant(
      email: "staff-reports-goals-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Reports Goals"
    )
    staff_identity.update!(staff: true)

    visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      started_at: Time.zone.now.change(usec: 0)
    )
    Ahoy::Event.create!(
      visit: visit,
      name: "signup",
      properties: {},
      time: Time.zone.now.change(usec: 0)
    )

    sign_in(staff_identity)

    get "/admin/analytics/reports", headers: INERTIA_HEADERS

    assert_response :success

    payload = JSON.parse(response.body)
    site = payload.fetch("props").fetch("site")

    assert_equal true, site.fetch("hasGoals")
  ensure
    Current.reset
  end

  test "reports shell capability booleans avoid loading full goal and property lists" do
    staff_identity, = create_tenant(
      email: "staff-reports-cheap-capabilities-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Reports Cheap Capabilities"
    )
    staff_identity.update!(staff: true)

    sign_in(staff_identity)

    original_available_goal_names = Analytics::Goals.method(:available_names)
    original_available_property_keys = Analytics::Properties.method(:available_keys)
    original_goals_available = Analytics::Goals.method(:available?)
    original_properties_available = Analytics::Properties.method(:available?)

    Analytics::Goals.define_singleton_method(:available_names) { raise "should not load goal names" }
    Analytics::Properties.define_singleton_method(:available_keys) { |_events = nil| raise "should not load property keys" }
    Analytics::Goals.define_singleton_method(:available?) { false }
    Analytics::Properties.define_singleton_method(:available?) { false }

    get "/admin/analytics/reports", headers: INERTIA_HEADERS

    assert_response :success
  ensure
    Analytics::Goals.define_singleton_method(:available_names, original_available_goal_names) if defined?(original_available_goal_names) && original_available_goal_names
    Analytics::Properties.define_singleton_method(:available_keys, original_available_property_keys) if defined?(original_available_property_keys) && original_available_property_keys
    Analytics::Goals.define_singleton_method(:available?, original_goals_available) if defined?(original_goals_available) && original_goals_available
    Analytics::Properties.define_singleton_method(:available?, original_properties_available) if defined?(original_properties_available) && original_properties_available
    Current.reset
  end

  test "reports shell preserves comma-containing filter values" do
    staff_identity, = create_tenant(
      email: "staff-reports-comma-filter-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Reports Comma Filter"
    )
    staff_identity.update!(staff: true)

    sign_in(staff_identity)

    get "/admin/analytics/reports?f=is,page,%2Fdocs%2Ffoo%2Cbar",
        headers: INERTIA_HEADERS

    assert_response :success

    payload = JSON.parse(response.body).fetch("props")
    query = payload.fetch("query")

    assert_equal "/docs/foo,bar", query.fetch("filters").fetch("page")
  ensure
    Current.reset
  end

  test "reports shell exposes default query separately from requested query" do
    staff_identity, = create_tenant(
      email: "staff-reports-defaults-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Reports Defaults"
    )
    staff_identity.update!(staff: true)

    sign_in(staff_identity)

    get "/admin/analytics/reports",
        params: {
          period: "custom",
          from: "2026-03-01",
          to: "2026-03-07",
          comparison: "custom",
          compare_from: "2026-02-01",
          compare_to: "2026-02-07",
          with_imported: "true"
        },
        headers: INERTIA_HEADERS

    assert_response :success

    payload = JSON.parse(response.body).fetch("props")
    query = payload.fetch("query")
    default_query = payload.fetch("defaultQuery")

    assert_equal "custom", query.fetch("period")
    assert_equal "custom", query.fetch("comparison")
    assert_equal true, json_key(query, "withImported", "with_imported")

    assert_equal "day", default_query.fetch("period")
    assert_nil default_query.fetch("comparison")
    assert_equal true, json_key(default_query, "matchDayOfWeek", "match_day_of_week")
    assert_equal false, json_key(default_query, "withImported", "with_imported")
    assert_equal({}, default_query.fetch("filters"))
    assert_equal({}, default_query.fetch("labels"))
  ensure
    Current.reset
  end

  test "reports shell includes initial analytics boot payload" do
    staff_identity, = create_tenant(
      email: "staff-reports-boot-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Reports Boot"
    )
    staff_identity.update!(staff: true)

    sign_in(staff_identity)

    get "/admin/analytics/reports", headers: INERTIA_HEADERS

    assert_response :success

    payload = JSON.parse(response.body).fetch("props")
    boot = payload.fetch("boot")

    assert boot.key?("topStats")
    assert boot.key?("mainGraph")
    assert boot.key?("sources")
    assert boot.key?("pages")
    assert boot.key?("locations")
    assert boot.key?("devices")
  ensure
    Current.reset
  end

  test "reports shell infers device version mode from browser version filters" do
    staff_identity, = create_tenant(
      email: "staff-reports-device-versions-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Reports Device Versions"
    )
    staff_identity.update!(staff: true)

    Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      browser: "Chrome",
      browser_version: "135.0",
      started_at: Time.zone.now.change(usec: 0)
    )
    Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      browser: "Chrome",
      browser_version: "136.0",
      started_at: Time.zone.now.change(usec: 0)
    )

    sign_in(staff_identity)

    get "/admin/analytics/reports?period=day&f=is,browser_version,136.0",
        headers: INERTIA_HEADERS

    assert_response :success

    payload = JSON.parse(response.body).fetch("props")
    boot = payload.fetch("boot")
    ui = boot.fetch("ui")
    devices = boot.fetch("devices")

    assert_equal "browsers", json_key(ui, "devicesBaseMode", "devices_base_mode")
    assert_equal "browser-versions", json_key(ui, "devicesMode", "devices_mode")
    assert_equal [ "136.0" ], devices.fetch("results").map { |row| row.fetch("name") }
  ensure
    Current.reset
  end

  test "reports shell ignores namespaced dashboard url params" do
    staff_identity, = create_tenant(
      email: "staff-reports-ui-params-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Reports UI Params"
    )
    staff_identity.update!(staff: true)

    sign_in(staff_identity)

    get "/admin/analytics/reports?period=7d&graph_metric=views_per_visit&graph_interval=hour&pages_mode=entry&behaviors_mode=props&behaviors_funnel=Signup&behaviors_property=Plan",
        headers: INERTIA_HEADERS

    assert_response :success

    payload = JSON.parse(response.body).fetch("props")
    query = payload.fetch("query")

    assert_equal "7d", query.fetch("period")
    refute query.key?("metric")
    refute query.key?("interval")
    refute query.key?("mode")
    refute query.key?("funnel")
  ensure
    Current.reset
  end

  private
    def json_key(hash, *keys)
      key = keys.find { |candidate| hash.key?(candidate) }
      raise KeyError, "missing keys: #{keys.join(', ')}" unless key

      hash.fetch(key)
    end
end
