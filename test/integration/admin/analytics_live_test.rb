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
    Analytics::SiteBoundary.delete_all if defined?(Analytics::SiteBoundary)
    Analytics::Site.delete_all if defined?(Analytics::Site)
    AnalyticsProfileKey.delete_all
    AnalyticsProfile.delete_all
  end

  test "live view exposes camelCase initial stats props" do
    staff_identity, = create_tenant(
      email: "staff-live-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Live"
    )
    staff_identity.update!(staff: true)
    site = Analytics::Bootstrap.ensure_default_site!(host: "localhost")

    sign_in(staff_identity)

    get live_path_for(site), headers: INERTIA_HEADERS

    assert_response :success

    props = JSON.parse(response.body).fetch("props")

    assert props.key?("initialStats")
    refute props.key?("initial_stats")

    stats = props.fetch("initialStats")
    assert props.key?("liveSubscriptionToken")
    assert_equal(
      "analytics:#{props.fetch("site").fetch("id")}",
      Analytics::LiveState.resolve_subscription_stream(props.fetch("liveSubscriptionToken"))
    )
    assert_equal 0, stats.fetch("currentVisitors")
    assert_equal 0, stats.fetch("todaySessions").fetch("count")
    assert_equal [], stats.fetch("sessionsByLocation")
    assert_equal [], stats.fetch("visitorDots")
    assert_equal [], stats.fetch("liveSessions")
    assert_equal [], stats.fetch("recentEvents")
  ensure
    Current.reset
  end

  test "singleton live route stays on the generic live shell" do
    staff_identity, = create_tenant(
      email: "staff-live-redirect-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Live Redirect"
    )
    staff_identity.update!(staff: true)

    site = Analytics::Bootstrap.ensure_default_site!(host: "localhost")

    sign_in(staff_identity)

    get "/admin/analytics/live", headers: INERTIA_HEADERS

    assert_response :success
  ensure
    Current.reset
  end

  test "legacy live route redirects ambiguous multi-site traffic to analytics settings" do
    staff_identity, = create_tenant(
      email: "staff-live-ambiguous-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Live Ambiguous"
    )
    staff_identity.update!(staff: true)

    Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    Analytics::Site.create!(name: "App", canonical_hostname: "app.example.test")

    sign_in(staff_identity)

    get "/admin/analytics/live", headers: INERTIA_HEADERS

    assert_redirected_to "/admin/settings/analytics"
  ensure
    Current.reset
  end

  test "live view exposes site-scoped reports and settings paths" do
    staff_identity, = create_tenant(
      email: "staff-live-site-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Live Site"
    )
    staff_identity.update!(staff: true)

    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test", time_zone: "UTC")
    Analytics::Site.create!(name: "App", canonical_hostname: "app.example.test", time_zone: "UTC")

    sign_in(staff_identity)

    get "/admin/analytics/sites/#{site.public_id}/live", headers: INERTIA_HEADERS

    assert_response :success

    site_payload = JSON.parse(response.body).fetch("props").fetch("site")
    assert_equal site.public_id, site_payload.fetch("id")
    assert_equal "/admin/analytics/sites/#{site.public_id}", site_payload.fetch("paths").fetch("reports")
    assert_equal "/admin/settings/analytics?site=#{site.public_id}", site_payload.fetch("paths").fetch("settings")
  ensure
    Current.reset
  end

  test "live view includes live sessions and recent events payloads" do
    staff_identity, = create_tenant(
      email: "staff-live-profile-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Live Profile"
    )
    staff_identity.update!(staff: true)

    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")

    profile = AnalyticsProfile.create!(
      analytics_site: site,
      status: AnalyticsProfile::STATUS_ANONYMOUS,
      traits: { display_name: "turquoise scorpion" },
      first_seen_at: 20.minutes.ago,
      last_seen_at: 1.minute.ago
    )

    visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      analytics_site: site,
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
      analytics_site: site,
      name: "scroll_to_pricing",
      properties: { page: "/" },
      time: 1.minute.ago.change(usec: 0)
    )
    Ahoy::Event.create!(
      visit: visit,
      analytics_site: site,
      name: "pageview",
      properties: { page: "/" },
      time: 45.seconds.ago.change(usec: 0)
    )
    Ahoy::Event.create!(
      visit: visit,
      analytics_site: site,
      name: "engagement",
      properties: { page: "/" },
      time: 50.seconds.ago.change(usec: 0)
    )

    sign_in(staff_identity)

    get live_path_for(site), headers: INERTIA_HEADERS

    assert_response :success

    stats = JSON.parse(response.body).fetch("props").fetch("initialStats")
    live_session = stats.fetch("liveSessions").first
    recent_event = stats.fetch("recentEvents").first

    assert_equal visit.id, live_session.fetch("visitId")
    assert_equal "turquoise scorpion", live_session.fetch("name")
    assert_equal "Spain", live_session.fetch("country")
    assert_equal "ES", live_session.fetch("countryCode")
    assert_equal "Barcelona, Spain", live_session.fetch("locationLabel")
    assert_equal "indiehackers.com", live_session.fetch("source")
    assert_equal true, live_session.fetch("active")
    assert_equal "turquoise scorpion", recent_event.fetch("name")
    assert_equal "Viewed page /", recent_event.fetch("label")
    assert_equal "ES", recent_event.fetch("countryCode")
    assert_equal "Barcelona, Spain", recent_event.fetch("locationLabel")
    assert_equal live_session.fetch("sessionId"), recent_event.fetch("sessionId")
    assert_equal 1, stats.fetch("recentEvents").count { |event| event.fetch("label") == "Viewed page /" }
    assert_equal 1, live_session.fetch("recentEvents").count { |event| event.fetch("label") == "Viewed page /" }
  ensure
    Current.reset
  end

  private
    def live_path_for(site)
      Analytics::Site.sole_active == site ? "/admin/analytics/live" : "/admin/analytics/sites/#{site.public_id}/live"
    end
end
