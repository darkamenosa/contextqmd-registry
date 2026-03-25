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

    original_available_goal_names = Ahoy::Visit.method(:available_goal_names)
    original_available_property_keys = Ahoy::Visit.method(:available_property_keys)
    original_goals_available = Ahoy::Visit.method(:goals_available?)
    original_properties_available = Ahoy::Visit.method(:properties_available?)

    Ahoy::Visit.define_singleton_method(:available_goal_names) { raise "should not load goal names" }
    Ahoy::Visit.define_singleton_method(:available_property_keys) { |_events = nil| raise "should not load property keys" }
    Ahoy::Visit.define_singleton_method(:goals_available?) { false }
    Ahoy::Visit.define_singleton_method(:properties_available?) { false }

    get "/admin/analytics/reports", headers: INERTIA_HEADERS

    assert_response :success
  ensure
    Ahoy::Visit.define_singleton_method(:available_goal_names, original_available_goal_names) if defined?(original_available_goal_names) && original_available_goal_names
    Ahoy::Visit.define_singleton_method(:available_property_keys, original_available_property_keys) if defined?(original_available_property_keys) && original_available_property_keys
    Ahoy::Visit.define_singleton_method(:goals_available?, original_goals_available) if defined?(original_goals_available) && original_goals_available
    Ahoy::Visit.define_singleton_method(:properties_available?, original_properties_available) if defined?(original_properties_available) && original_properties_available
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
