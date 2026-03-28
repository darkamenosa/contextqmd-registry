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
    AnalyticsProfileSession.delete_all if defined?(AnalyticsProfileSession)
    AnalyticsProfileSummary.delete_all if defined?(AnalyticsProfileSummary)
    AnalyticsProfileKey.delete_all
    AnalyticsProfile.delete_all
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
    assert_equal [], stats.fetch("liveSessions")
    assert_equal [], stats.fetch("recentEvents")
  ensure
    Current.reset
  end

  test "live view includes live sessions and recent events payloads" do
    staff_identity, = create_tenant(
      email: "staff-live-profile-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Live Profile"
    )
    staff_identity.update!(staff: true)

    profile = AnalyticsProfile.create!(
      status: AnalyticsProfile::STATUS_ANONYMOUS,
      traits: { display_name: "turquoise scorpion" },
      first_seen_at: 20.minutes.ago,
      last_seen_at: 1.minute.ago
    )

    visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      analytics_profile: profile,
      browser_id: SecureRandom.uuid,
      started_at: 4.minutes.ago.change(usec: 0),
      latitude: 41.3874,
      longitude: 2.1686,
      country: "Spain",
      city: "Barcelona",
      device_type: "Desktop",
      os: "Mac OS",
      browser: "Chrome",
      referrer: "https://www.indiehackers.com/post/example",
      referring_domain: "indiehackers.com",
      landing_page: "https://example.test/"
    )

    Ahoy::Event.create!(
      visit: visit,
      name: "scroll_to_pricing",
      properties: { page: "/" },
      time: 1.minute.ago.change(usec: 0)
    )
    Ahoy::Event.create!(
      visit: visit,
      name: "pageview",
      properties: { page: "/" },
      time: 45.seconds.ago.change(usec: 0)
    )
    Ahoy::Event.create!(
      visit: visit,
      name: "engagement",
      properties: { page: "/" },
      time: 50.seconds.ago.change(usec: 0)
    )

    sign_in(staff_identity)

    get "/admin/analytics/live", headers: INERTIA_HEADERS

    assert_response :success

    stats = JSON.parse(response.body).fetch("props").fetch("initialStats")
    live_session = stats.fetch("liveSessions").first
    recent_event = stats.fetch("recentEvents").first

    assert_equal visit.id, live_session.fetch("visitId")
    assert_equal "turquoise scorpion", live_session.fetch("name")
    assert_equal "Spain", live_session.fetch("country")
    assert_equal "ES", live_session.fetch("countryCode")
    assert_equal "indiehackers.com", live_session.fetch("source")
    assert_equal true, live_session.fetch("active")
    assert_equal "turquoise scorpion", recent_event.fetch("name")
    assert_equal "Viewed page /", recent_event.fetch("label")
    assert_equal "ES", recent_event.fetch("countryCode")
    assert_equal live_session.fetch("sessionId"), recent_event.fetch("sessionId")
    assert_equal 1, stats.fetch("recentEvents").count { |event| event.fetch("label") == "Viewed page /" }
    assert_equal 1, live_session.fetch("recentEvents").count { |event| event.fetch("label") == "Viewed page /" }
  ensure
    Current.reset
  end
end
