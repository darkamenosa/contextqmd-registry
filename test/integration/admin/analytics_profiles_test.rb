# frozen_string_literal: true

require "test_helper"

class Admin::AnalyticsProfilesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
    AnalyticsProfileSession.delete_all if defined?(AnalyticsProfileSession)
    AnalyticsProfileSummary.delete_all if defined?(AnalyticsProfileSummary)
    AnalyticsProfileKey.delete_all
    AnalyticsProfile.delete_all
  end

  test "profiles index returns report-scoped visitor rows" do
    staff_identity, = create_tenant(
      email: "staff-profiles-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Profiles"
    )
    staff_identity.update!(staff: true)

    profile = AnalyticsProfile.create!(
      status: AnalyticsProfile::STATUS_ANONYMOUS,
      traits: { display_name: "turquoise scorpion" },
      first_seen_at: 10.minutes.ago,
      last_seen_at: 2.minutes.ago
    )

    visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      analytics_profile: profile,
      browser_id: SecureRandom.uuid,
      started_at: 4.minutes.ago.change(usec: 0),
      country: "Spain",
      city: "Barcelona",
      region: "Catalonia",
      device_type: "Desktop",
      os: "Mac OS",
      browser: "Chrome",
      referrer: "https://www.indiehackers.com/post/example",
      referring_domain: "indiehackers.com",
      landing_page: "https://example.test/"
    )

    Ahoy::Event.create!(
      visit: visit,
      name: "pageview",
      properties: { page: "/" },
      time: 3.minutes.ago.change(usec: 0)
    )

    visit.refresh_source_dimensions!
    AnalyticsProfile::Projection.rebuild(profile)
    profile.summary.update!(latest_context: {})

    sign_in(staff_identity)

    get "/admin/analytics/profiles",
        params: { period: "day", search: "barcelona" },
        headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    row = payload.fetch("results").first

    assert_equal "profiles", payload.fetch("kind")
    assert_equal "turquoise scorpion", row.fetch("name")
    assert_equal "Spain", row.fetch("country")
    assert_equal "Barcelona", row.fetch("city")
    assert_equal "indiehackers.com", row.fetch("source")
    assert_equal "/", row.fetch("currentPage")
    assert_equal 1, row.fetch("totalVisits")
    assert_equal 1, row.fetch("scopedVisits")
  ensure
    Current.reset
  end

  test "profile journey endpoint returns summary and session projections for selected profile" do
    staff_identity, = create_tenant(
      email: "staff-profile-journey-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Profile Journey"
    )
    staff_identity.update!(staff: true)

    profile = AnalyticsProfile.create!(
      status: AnalyticsProfile::STATUS_IDENTIFIED,
      traits: { display_name: "black emu" },
      first_seen_at: 1.hour.ago,
      last_seen_at: 5.minutes.ago
    )

    visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      analytics_profile: profile,
      browser_id: SecureRandom.uuid,
      started_at: 25.minutes.ago.change(usec: 0),
      country: "Czechia",
      city: "Prague",
      device_type: "Desktop",
      os: "Windows",
      browser: "Chrome",
      referrer: "https://www.google.com/search?q=contextqmd+analytics",
      referring_domain: "google.com",
      utm_source: "trustmrr",
      utm_medium: "referral",
      utm_campaign: "sponsor_card",
      landing_page: "https://example.test/course?ref=shipfast_pricing"
    )

    historical_visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      analytics_profile: profile,
      browser_id: SecureRandom.uuid,
      started_at: 3.days.ago.change(usec: 0),
      country: "Czechia",
      city: "Prague",
      device_type: "Mobile",
      os: "iOS",
      browser: "Safari",
      source_label: "Twitter",
      landing_page: "https://example.test/pricing"
    )

    Ahoy::Event.create!(
      visit: visit,
      name: "pageview",
      properties: { page: "/course" },
      time: 24.minutes.ago.change(usec: 0)
    )
    Ahoy::Event.create!(
      visit: visit,
      name: "scroll_to_pricing",
      properties: { page: "/course" },
      time: 23.minutes.ago.change(usec: 0)
    )
    Ahoy::Event.create!(
      visit: historical_visit,
      name: "pageview",
      properties: { page: "/pricing" },
      time: 3.days.ago.change(usec: 0)
    )

    sign_in(staff_identity)

    get "/admin/analytics/profiles/#{profile.public_id}",
        params: { period: "day", f: [ "is,page,/course" ] },
        headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)

    assert_equal "black emu", payload.fetch("profile").fetch("name")
    assert_equal "CZ", payload.fetch("profile").fetch("countryCode")
    assert_equal 2, payload.fetch("profile").fetch("totalSessions")
    assert_equal 2, payload.fetch("profile").fetch("devicesUsed").size
    assert_equal "CZ", payload.fetch("profile").fetch("locationsUsed").first.fetch("countryCode")
    assert_equal 2, payload.fetch("summary").fetch("sessions")
    assert_equal 2, payload.fetch("summary").fetch("pageviews")
    assert_equal 3, payload.fetch("summary").fetch("events")
    assert_equal 2, payload.fetch("activity").size
  ensure
    Current.reset
  end

  test "profile session endpoint returns session-scoped events" do
    staff_identity, = create_tenant(
      email: "staff-profile-session-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Profile Session"
    )
    staff_identity.update!(staff: true)

    profile = AnalyticsProfile.create!(
      status: AnalyticsProfile::STATUS_IDENTIFIED,
      traits: { display_name: "black emu" },
      first_seen_at: 1.hour.ago,
      last_seen_at: 5.minutes.ago
    )

    visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      analytics_profile: profile,
      browser_id: SecureRandom.uuid,
      started_at: 25.minutes.ago.change(usec: 0),
      country: "Czechia",
      city: "Prague",
      device_type: "Desktop",
      os: "Windows",
      browser: "Chrome",
      referrer: "https://www.google.com/search?q=contextqmd+analytics",
      referring_domain: "google.com",
      utm_source: "trustmrr",
      utm_medium: "referral",
      utm_campaign: "sponsor_card",
      landing_page: "https://example.test/course?ref=shipfast_pricing"
    )

    Ahoy::Event.create!(
      visit: visit,
      name: "pageview",
      properties: { page: "/course" },
      time: 24.minutes.ago.change(usec: 0)
    )
    Ahoy::Event.create!(
      visit: visit,
      name: "scroll_to_pricing",
      properties: { page: "/course" },
      time: 23.minutes.ago.change(usec: 0)
    )

    visit.refresh_source_dimensions!
    AnalyticsProfile::Projection.rebuild(profile)

    sign_in(staff_identity)

    get "/admin/analytics/profiles/#{profile.public_id}/sessions/#{visit.id}",
        params: { period: "day" },
        headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal visit.id, payload.fetch("session").fetch("visitId")
    assert_equal "CZ", payload.fetch("session").fetch("countryCode")
    assert_equal "trustmrr", payload.fetch("sourceSummary").fetch("sourceLabel")
    assert_equal "google.com", payload.fetch("sourceSummary").fetch("referringDomain")
    assert_equal "/course?ref=shipfast_pricing",
      payload.fetch("sourceSummary").fetch("landingPage")
    assert_equal "trustmrr", payload.fetch("sourceSummary").fetch("utmSource")
    assert_equal "referral", payload.fetch("sourceSummary").fetch("utmMedium")
    assert_equal "sponsor_card", payload.fetch("sourceSummary").fetch("utmCampaign")
    assert_equal [ "ref" ],
      payload.fetch("sourceSummary").fetch("trackerParams").map { |item| item.fetch("key") }
    assert_equal "contextqmd analytics",
      payload.fetch("sourceSummary").fetch("searchTerms").first.fetch("label")
    assert_equal [ "scroll_to_pricing on /course", "Viewed page /course" ],
      payload.fetch("events").map { |item| item.fetch("label") }
  ensure
    Current.reset
  end

  test "profile sessions index paginates projected sessions in session order" do
    staff_identity, = create_tenant(
      email: "staff-profile-sessions-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Profile Sessions"
    )
    staff_identity.update!(staff: true)

    profile = AnalyticsProfile.create!(
      status: AnalyticsProfile::STATUS_IDENTIFIED,
      traits: { display_name: "black emu" },
      first_seen_at: 2.hours.ago,
      last_seen_at: 5.minutes.ago
    )

    visits = 3.times.map do |index|
      visit = Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: SecureRandom.hex(16),
        analytics_profile: profile,
        browser_id: SecureRandom.uuid,
        started_at: (30.minutes.ago - index.hours).change(usec: 0),
        country: "Czechia",
        city: "Prague",
        device_type: "Desktop",
        os: "Windows",
        browser: "Chrome",
        landing_page: "https://example.test/session-#{index}"
      )

      Ahoy::Event.create!(
        visit: visit,
        name: "pageview",
        properties: { page: "/session-#{index}" },
        time: visit.started_at + 1.minute
      )

      visit
    end

    AnalyticsProfile::Projection.rebuild(profile)
    sign_in(staff_identity)

    get "/admin/analytics/profiles/#{profile.public_id}/sessions",
        params: { period: "day", limit: 2, page: 1 },
        headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal true, payload.fetch("hasMore")
    assert_equal visits.first.id, payload.fetch("sessions").first.fetch("visitId")
    assert_equal visits.second.id, payload.fetch("sessions").second.fetch("visitId")

    get "/admin/analytics/profiles/#{profile.public_id}/sessions",
        params: { period: "day", limit: 2, page: 2 },
        headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal false, payload.fetch("hasMore")
    assert_equal [ visits.third.id ], payload.fetch("sessions").map { |session| session.fetch("visitId") }
  ensure
    Current.reset
  end

  test "profile session endpoint suppresses engagement spam and dedupes repeated labels" do
    staff_identity, = create_tenant(
      email: "staff-profile-session-dedupe-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Profile Session Dedupe"
    )
    staff_identity.update!(staff: true)

    profile = AnalyticsProfile.create!(
      status: AnalyticsProfile::STATUS_IDENTIFIED,
      traits: { display_name: "black emu" },
      first_seen_at: 1.hour.ago,
      last_seen_at: 5.minutes.ago
    )

    visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      analytics_profile: profile,
      browser_id: SecureRandom.uuid,
      started_at: 25.minutes.ago.change(usec: 0),
      landing_page: "https://example.test/"
    )

    Ahoy::Event.create!(
      visit: visit,
      name: "pageview",
      properties: { page: "/" },
      time: 24.minutes.ago.change(usec: 0)
    )
    3.times do |index|
      Ahoy::Event.create!(
        visit: visit,
        name: "engagement",
        properties: { page: "/" },
        time: (23.minutes.ago + index.seconds).change(usec: 0)
      )
    end
    Ahoy::Event.create!(
      visit: visit,
      name: "pageview",
      properties: { page: "/" },
      time: 23.minutes.ago.change(usec: 0)
    )

    AnalyticsProfile::Projection.rebuild(profile)

    sign_in(staff_identity)

    get "/admin/analytics/profiles/#{profile.public_id}/sessions/#{visit.id}",
        params: { period: "day" },
        headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal [ "Viewed page /" ], payload.fetch("events").map { |item| item.fetch("label") }
  ensure
    Current.reset
  end
end
