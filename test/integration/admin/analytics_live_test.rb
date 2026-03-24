# frozen_string_literal: true

require "test_helper"

class Admin::AnalyticsLiveTest < ActionDispatch::IntegrationTest
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
  end

  test "live view exposes camelCase initial stats props" do
    staff_identity, = create_tenant(
      email: "staff-live-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Live"
    )
    staff_identity.update!(staff: true)

    sign_in(staff_identity)

    get "/admin/analytics/live", headers: INERTIA_HEADERS

    assert_response :success

    props = JSON.parse(response.body).fetch("props")

    assert props.key?("initialStats")
    refute props.key?("initial_stats")

    stats = props.fetch("initialStats")
    assert_equal 0, stats.fetch("currentVisitors")
    assert_equal 0, stats.fetch("todaySessions").fetch("count")
    assert_equal [], stats.fetch("sessionsByLocation")
    assert_equal [], stats.fetch("visitorDots")
  ensure
    Current.reset
  end
end
