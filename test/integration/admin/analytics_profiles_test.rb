# frozen_string_literal: true

require "test_helper"

class Admin::AnalyticsProfilesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
    Analytics::GoogleSearchConsole::QueryRow.delete_all
    Analytics::GoogleSearchConsole::Sync.delete_all
    Analytics::GoogleSearchConsoleConnection.delete_all
    Analytics::SiteBoundary.delete_all
    Analytics::Site.delete_all
    AnalyticsProfileSession.delete_all if defined?(AnalyticsProfileSession)
    AnalyticsProfileSummary.delete_all if defined?(AnalyticsProfileSummary)
    AnalyticsProfileKey.delete_all
    AnalyticsProfile.delete_all
  end

  private
    def default_analytics_site
      @default_analytics_site ||= Analytics::Site.create!(
        name: "Default",
        canonical_hostname: "www.example.com"
      )
    end

    def profiles_path_for(site)
      "/admin/analytics/sites/#{site.public_id}/profiles"
    end

    def profile_path_for(site, profile)
      "#{profiles_path_for(site)}/#{profile.public_id}"
    end

    def profile_sessions_path_for(site, profile)
      "#{profiles_path_for(site)}/#{profile.public_id}/sessions"
    end

    def profile_session_path_for(site, profile, visit)
      "#{profile_sessions_path_for(site, profile)}/#{visit.id}"
    end

  public

  test "profiles index returns report-scoped visitor rows" do
    staff_identity, = create_tenant(
      email: "staff-profiles-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Profiles"
    )
    staff_identity.update!(staff: true)

    profile = AnalyticsProfile.create!(
      analytics_site: default_analytics_site,
      status: AnalyticsProfile::STATUS_ANONYMOUS,
      traits: { display_name: "turquoise scorpion" },
      first_seen_at: 10.minutes.ago,
      last_seen_at: 2.minutes.ago
    )

    visit = Ahoy::Visit.create!(
      analytics_site: default_analytics_site,
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
      analytics_site: default_analytics_site,
      visit: visit,
      name: "pageview",
      properties: { page: "/" },
      time: 3.minutes.ago.change(usec: 0)
    )

    visit.refresh_source_dimensions!
    AnalyticsProfile::Projection.rebuild(profile)
    profile.summary.update!(latest_context: {})

    sign_in(staff_identity)

    get profiles_path_for(default_analytics_site),
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

  test "profiles index searches generated anonymous display names through projections" do
    staff_identity, = create_tenant(
      email: "staff-profiles-generated-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Profiles Generated"
    )
    staff_identity.update!(staff: true)

    profile = AnalyticsProfile.create!(
      analytics_site: default_analytics_site,
      status: AnalyticsProfile::STATUS_ANONYMOUS,
      first_seen_at: 15.minutes.ago,
      last_seen_at: 4.minutes.ago
    )

    visit = Ahoy::Visit.create!(
      analytics_site: default_analytics_site,
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      analytics_profile: profile,
      browser_id: SecureRandom.uuid,
      started_at: 6.minutes.ago.change(usec: 0),
      country: "Spain",
      city: "Barcelona",
      region: "Catalonia",
      device_type: "Desktop",
      os: "Mac OS",
      browser: "Chrome",
      landing_page: "https://example.test/generated"
    )

    Ahoy::Event.create!(
      analytics_site: default_analytics_site,
      visit: visit,
      name: "pageview",
      properties: { page: "/generated" },
      time: 5.minutes.ago.change(usec: 0)
    )

    generated_name = profile.display_name

    AnalyticsProfile::Projection.rebuild(profile)
    sign_in(staff_identity)

    get profiles_path_for(default_analytics_site),
        params: { period: "day", search: generated_name.split.first },
        headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    row = payload.fetch("results").first

    assert_equal generated_name, row.fetch("name")
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
      analytics_site: default_analytics_site,
      status: AnalyticsProfile::STATUS_IDENTIFIED,
      traits: { display_name: "black emu" },
      first_seen_at: 1.hour.ago,
      last_seen_at: 5.minutes.ago
    )

    visit = Ahoy::Visit.create!(
      analytics_site: default_analytics_site,
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
      analytics_site: default_analytics_site,
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
      analytics_site: default_analytics_site,
      visit: visit,
      name: "pageview",
      properties: { page: "/course" },
      time: 24.minutes.ago.change(usec: 0)
    )
    Ahoy::Event.create!(
      analytics_site: default_analytics_site,
      visit: visit,
      name: "scroll_to_pricing",
      properties: { page: "/course" },
      time: 23.minutes.ago.change(usec: 0)
    )
    Ahoy::Event.create!(
      analytics_site: default_analytics_site,
      visit: historical_visit,
      name: "pageview",
      properties: { page: "/pricing" },
      time: 3.days.ago.change(usec: 0)
    )

    sign_in(staff_identity)

    get profile_path_for(default_analytics_site, profile),
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

    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    profile = AnalyticsProfile.create!(
      analytics_site: site,
      status: AnalyticsProfile::STATUS_IDENTIFIED,
      traits: { display_name: "black emu" },
      first_seen_at: 1.hour.ago,
      last_seen_at: 5.minutes.ago
    )

    visit = Ahoy::Visit.create!(
      analytics_site: site,
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
      referrer: "https://www.google.com/search?q=totally+wrong+query",
      referring_domain: "google.com",
      utm_source: "google",
      utm_medium: "organic",
      utm_campaign: "spring_launch",
      landing_page: "https://docs.example.test/course?ref=shipfast_pricing"
    )

    connection = Analytics::GoogleSearchConsoleConnection.rotate_for_site!(
      site: site,
      attributes: {
        google_uid: "google-user-#{SecureRandom.hex(4)}",
        google_email: "owner@example.com",
        access_token: "access-token",
        refresh_token: "refresh-token",
        expires_at: 1.hour.from_now,
        scopes: Analytics::GoogleSearchConsole::Client::SCOPES,
        metadata: {},
        property_identifier: "sc-domain:docs.example.test",
        property_type: "domain",
        permission_level: "siteOwner",
        last_verified_at: Time.current
      }
    )
    sync = connection.syncs.create!(
      property_identifier: connection.property_identifier,
      search_type: "web",
      from_date: visit.started_at.to_date,
      to_date: visit.started_at.to_date,
      started_at: Time.current,
      finished_at: Time.current,
      status: Analytics::GoogleSearchConsole::Sync::STATUS_SUCCEEDED
    )
    Analytics::GoogleSearchConsole::QueryRow.create!(
      analytics_site: site,
      sync: sync,
      date: visit.started_at.to_date,
      search_type: "web",
      query: "contextqmd analytics",
      page: "https://docs.example.test/course",
      country: "USA",
      device: "mobile",
      clicks: 16,
      impressions: 40,
      position_impressions_sum: 100
    )
    Analytics::GoogleSearchConsole::QueryRow.create!(
      analytics_site: site,
      sync: sync,
      date: visit.started_at.to_date,
      search_type: "web",
      query: "analytics",
      page: "https://docs.example.test/course",
      country: "USA",
      device: "mobile",
      clicks: 4,
      impressions: 20,
      position_impressions_sum: 70
    )

    Ahoy::Event.create!(
      visit: visit,
      analytics_site: site,
      name: "pageview",
      properties: { page: "/course" },
      time: 24.minutes.ago.change(usec: 0)
    )
    Ahoy::Event.create!(
      visit: visit,
      analytics_site: site,
      name: "scroll_to_pricing",
      properties: { page: "/course" },
      time: 23.minutes.ago.change(usec: 0)
    )

    visit.refresh_source_dimensions!
    AnalyticsProfile::Projection.rebuild(profile)

    sign_in(staff_identity)

    get "/admin/analytics/sites/#{site.public_id}/profiles/#{profile.public_id}/sessions/#{visit.id}",
        params: { period: "day" },
        headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal visit.id, payload.fetch("session").fetch("visitId")
    assert_equal "CZ", payload.fetch("session").fetch("countryCode")
    assert_equal "Google", payload.fetch("sourceSummary").fetch("sourceLabel")
    assert_equal "google.com", payload.fetch("sourceSummary").fetch("referringDomain")
    assert_equal "/course?ref=shipfast_pricing",
      payload.fetch("sourceSummary").fetch("landingPage")
    assert_equal "google", payload.fetch("sourceSummary").fetch("utmSource")
    assert_equal "organic", payload.fetch("sourceSummary").fetch("utmMedium")
    assert_equal "spring_launch", payload.fetch("sourceSummary").fetch("utmCampaign")
    assert_equal [ "ref" ],
      payload.fetch("sourceSummary").fetch("trackerParams").map { |item| item.fetch("key") }
    assert_equal "contextqmd analytics",
      payload.fetch("sourceSummary").fetch("searchTerms").first.fetch("label")
    assert_equal 80,
      payload.fetch("sourceSummary").fetch("searchTerms").first.fetch("probability")
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
      analytics_site: default_analytics_site,
      status: AnalyticsProfile::STATUS_IDENTIFIED,
      traits: { display_name: "black emu" },
      first_seen_at: 2.hours.ago,
      last_seen_at: 5.minutes.ago
    )

    visits = 3.times.map do |index|
      visit = Ahoy::Visit.create!(
        analytics_site: default_analytics_site,
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
        analytics_site: default_analytics_site,
        visit: visit,
        name: "pageview",
        properties: { page: "/session-#{index}" },
        time: visit.started_at + 1.minute
      )

      visit
    end

    AnalyticsProfile::Projection.rebuild(profile)
    sign_in(staff_identity)

    get profile_sessions_path_for(default_analytics_site, profile),
        params: { period: "day", limit: 2, page: 1 },
        headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal true, payload.fetch("hasMore")
    assert_equal visits.first.id, payload.fetch("sessions").first.fetch("visitId")
    assert_equal visits.second.id, payload.fetch("sessions").second.fetch("visitId")

    get profile_sessions_path_for(default_analytics_site, profile),
        params: { period: "day", limit: 2, page: 2 },
        headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal false, payload.fetch("hasMore")
    assert_equal [ visits.third.id ], payload.fetch("sessions").map { |session| session.fetch("visitId") }
  ensure
    Current.reset
  end

  test "profile sessions index filters projected sessions by selected day" do
    staff_identity, = create_tenant(
      email: "staff-profile-sessions-date-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Profile Sessions Date"
    )
    staff_identity.update!(staff: true)

    profile = AnalyticsProfile.create!(
      analytics_site: default_analytics_site,
      status: AnalyticsProfile::STATUS_IDENTIFIED,
      traits: { display_name: "black emu" },
      first_seen_at: 2.days.ago,
      last_seen_at: 5.minutes.ago
    )

    older_visit = Ahoy::Visit.create!(
      analytics_site: default_analytics_site,
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      analytics_profile: profile,
      browser_id: SecureRandom.uuid,
      started_at: Time.zone.parse("2026-03-28 23:15:00"),
      country: "Czechia",
      city: "Prague",
      device_type: "Desktop",
      os: "Windows",
      browser: "Chrome",
      landing_page: "https://example.test/older"
    )

    filtered_visit = Ahoy::Visit.create!(
      analytics_site: default_analytics_site,
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      analytics_profile: profile,
      browser_id: SecureRandom.uuid,
      started_at: Time.zone.parse("2026-03-29 08:30:00"),
      country: "Czechia",
      city: "Prague",
      device_type: "Desktop",
      os: "Windows",
      browser: "Chrome",
      landing_page: "https://example.test/filtered"
    )

    [ older_visit, filtered_visit ].each do |visit|
      Ahoy::Event.create!(
        analytics_site: default_analytics_site,
        visit: visit,
        name: "pageview",
        properties: { page: "/#{visit.id}" },
        time: visit.started_at + 1.minute
      )
    end

    AnalyticsProfile::Projection.rebuild(profile)
    sign_in(staff_identity)

    get profile_sessions_path_for(default_analytics_site, profile),
        params: { period: "day", limit: 20, page: 1, date: "2026-03-29" },
        headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal [ filtered_visit.id ], payload.fetch("sessions").map { |session| session.fetch("visitId") }
    assert_equal false, payload.fetch("hasMore")
  ensure
    Current.reset
  end

  test "profile sessions index rejects invalid date filters" do
    staff_identity, = create_tenant(
      email: "staff-profile-sessions-invalid-date-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Profile Sessions Invalid Date"
    )
    staff_identity.update!(staff: true)

    profile = AnalyticsProfile.create!(
      analytics_site: default_analytics_site,
      status: AnalyticsProfile::STATUS_IDENTIFIED,
      traits: { display_name: "black emu" },
      first_seen_at: 1.hour.ago,
      last_seen_at: 5.minutes.ago
    )

    sign_in(staff_identity)

    get profile_sessions_path_for(default_analytics_site, profile),
        params: { period: "day", limit: 20, page: 1, date: "2026-3-29" },
        headers: { "ACCEPT" => "application/json" }

    assert_response :unprocessable_content
    assert_equal "Invalid date", JSON.parse(response.body).fetch("error")
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
      analytics_site: default_analytics_site,
      status: AnalyticsProfile::STATUS_IDENTIFIED,
      traits: { display_name: "black emu" },
      first_seen_at: 1.hour.ago,
      last_seen_at: 5.minutes.ago
    )

    visit = Ahoy::Visit.create!(
      analytics_site: default_analytics_site,
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      analytics_profile: profile,
      browser_id: SecureRandom.uuid,
      started_at: 25.minutes.ago.change(usec: 0),
      landing_page: "https://example.test/"
    )

    Ahoy::Event.create!(
      analytics_site: default_analytics_site,
      visit: visit,
      name: "pageview",
      properties: { page: "/" },
      time: 24.minutes.ago.change(usec: 0)
    )
    3.times do |index|
      Ahoy::Event.create!(
        analytics_site: default_analytics_site,
        visit: visit,
        name: "engagement",
        properties: { page: "/" },
        time: (23.minutes.ago + index.seconds).change(usec: 0)
      )
    end
    Ahoy::Event.create!(
      analytics_site: default_analytics_site,
      visit: visit,
      name: "pageview",
      properties: { page: "/" },
      time: 23.minutes.ago.change(usec: 0)
    )

    AnalyticsProfile::Projection.rebuild(profile)

    sign_in(staff_identity)

    get profile_session_path_for(default_analytics_site, profile, visit),
        params: { period: "day" },
        headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal [ "Viewed page /" ], payload.fetch("events").map { |item| item.fetch("label") }
  ensure
    Current.reset
  end
end
