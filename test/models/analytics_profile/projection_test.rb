# frozen_string_literal: true

require "test_helper"

class AnalyticsProfileProjectionTest < ActiveSupport::TestCase
  setup do
    Analytics::VisitSummary.delete_all if Analytics::VisitSummary.available?
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
    AnalyticsProfileSummary.delete_all if defined?(AnalyticsProfileSummary)
    AnalyticsProfileKey.delete_all
    AnalyticsProfile.delete_all
    Analytics::SiteBoundary.delete_all
    Analytics::Site.delete_all
  end

  def build_profile_with_visit(
    site_name: "Docs",
    hostname: "docs.example.test",
    started_at: 5.minutes.ago.change(usec: 0),
    landing_page: "https://docs.example.test/pricing"
  )
    site = Analytics::Site.create!(name: site_name, canonical_hostname: hostname)
    profile = AnalyticsProfile.create!(
      analytics_site: site,
      status: AnalyticsProfile::STATUS_ANONYMOUS,
      first_seen_at: 10.minutes.ago,
      last_seen_at: 1.minute.ago
    )

    visit = Ahoy::Visit.create!(
      analytics_site: site,
      analytics_profile: profile,
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      browser_id: SecureRandom.uuid,
      started_at:,
      country: "Spain",
      city: "Barcelona",
      device_type: "Desktop",
      browser: "Chrome",
      os: "Mac OS",
      landing_page:
    )

    [ site, profile, visit ]
  end

  test "project_visit upserts an existing session row" do
    site, profile, visit = build_profile_with_visit

    Ahoy::Event.create!(
      analytics_site: site,
      visit: visit,
      name: "pageview",
      properties: { page: "/pricing" },
      time: 4.minutes.ago.change(usec: 0)
    )

    Analytics::VisitSummary.create!(
      visit: visit,
      analytics_profile: profile,
      analytics_site: site,
      started_at: visit.started_at,
      visitor_token: visit.visitor_token,
      last_event_at: visit.started_at,
      country: "Spain",
      city: "Barcelona",
      device_type: "Desktop",
      browser: "Safari",
      os: "Mac OS",
      source: "Direct / None",
      duration_seconds: 0,
      pageviews_count: 0,
      events_count: 0,
      page_paths: [],
      event_names: []
    )

    AnalyticsProfile::Projection.project_visit(visit)

    session = Analytics::VisitSummary.find_by!(visit_id: visit.id)
    assert_equal profile.id, session.analytics_profile_id
    assert_equal site.id, session.analytics_site_id
    assert_equal "/pricing", session.entry_page
    assert_equal "/pricing", session.current_page
    assert_equal 1, session.pageviews_count
    assert_equal [ "/pricing" ], session.page_paths
    assert_equal [ "pageview" ], session.event_names
  end

  test "project_visit is idempotent across repeated replays" do
    site, profile, visit = build_profile_with_visit

    Ahoy::Event.create!(
      analytics_site: site,
      visit: visit,
      name: "pageview",
      properties: { page: "/pricing" },
      time: 4.minutes.ago.change(usec: 0)
    )
    Ahoy::Event.create!(
      analytics_site: site,
      visit: visit,
      name: "engagement",
      properties: { page: "/pricing", engaged_ms: 2400 },
      time: 3.minutes.ago.change(usec: 0)
    )

    2.times { AnalyticsProfile::Projection.project_visit(visit) }

    assert_equal 1, Analytics::VisitSummary.where(visit_id: visit.id).count
    assert_equal 1, AnalyticsProfileSummary.where(analytics_profile_id: profile.id).count

    session = Analytics::VisitSummary.find_by!(visit_id: visit.id)
    summary = AnalyticsProfileSummary.find_by!(analytics_profile_id: profile.id)

    assert_equal 2, session.events_count
    assert_equal [ "/pricing" ], session.page_paths
    assert_equal [ "pageview", "engagement" ], session.event_names
    assert_equal 2400, session.engaged_ms_total if session.respond_to?(:engaged_ms_total)

    assert_equal 1, summary.total_sessions
    assert_equal 1, summary.total_visits
    assert_equal 1, summary.total_pageviews
    assert_equal 2, summary.total_events
    assert_equal "/pricing", summary.latest_current_page
  end

  test "project_visit removes stale derived rows when a visit no longer belongs to a profile" do
    site, profile, visit = build_profile_with_visit

    Ahoy::Event.create!(
      analytics_site: site,
      visit: visit,
      name: "pageview",
      properties: { page: "/pricing" },
      time: 4.minutes.ago.change(usec: 0)
    )

    AnalyticsProfile::Projection.project_visit(visit)
    assert_equal 1, Analytics::VisitSummary.where(visit_id: visit.id).count
    assert_equal 1, AnalyticsProfileSummary.where(analytics_profile_id: profile.id).count

    visit.update_columns(analytics_profile_id: nil)

    AnalyticsProfile::Projection.project_visit(visit, previous_profile_id: profile.id)

    assert_equal 1, Analytics::VisitSummary.where(visit_id: visit.id).count
    assert_equal 0, AnalyticsProfileSummary.where(analytics_profile_id: profile.id).count
    assert_nil Analytics::VisitSummary.find_by!(visit_id: visit.id).analytics_profile_id
  end

  test "project_visit preserves first-seen ordering for distinct event names and page paths" do
    site, _profile, visit = build_profile_with_visit

    Ahoy::Event.create!(
      analytics_site: site,
      visit: visit,
      name: "pageview",
      properties: { page: "/pricing" },
      time: 4.minutes.ago.change(usec: 0)
    )
    Ahoy::Event.create!(
      analytics_site: site,
      visit: visit,
      name: "engagement",
      properties: { page: "/pricing", engaged_ms: 1200 },
      time: 3.minutes.ago.change(usec: 0)
    )
    Ahoy::Event.create!(
      analytics_site: site,
      visit: visit,
      name: "signup",
      properties: { page: "/docs" },
      time: 2.minutes.ago.change(usec: 0)
    )
    Ahoy::Event.create!(
      analytics_site: site,
      visit: visit,
      name: "pageview",
      properties: { page: "/pricing" },
      time: 1.minute.ago.change(usec: 0)
    )

    AnalyticsProfile::Projection.project_visit(visit)

    session = Analytics::VisitSummary.find_by!(visit_id: visit.id)
    assert_equal [ "pageview", "engagement", "signup" ], session.event_names
    assert_equal [ "/pricing", "/docs" ], session.page_paths
    assert_equal "/pricing", session.entry_page
    assert_equal "/pricing", session.exit_page
    assert_equal "/docs", session.current_page
    assert_equal 2, session.pageviews_count
    assert_equal 4, session.events_count
    assert_equal 1200, session.engaged_ms_total if session.respond_to?(:engaged_ms_total)
  end

  test "project_visit uses visit summaries when raw visit events are gone" do
    site, _profile, visit = build_profile_with_visit

    pageview = Ahoy::Event.create!(
      analytics_site: site,
      visit: visit,
      name: "pageview",
      properties: { page: "/pricing" },
      time: 4.minutes.ago.change(usec: 0)
    )
    engagement = Ahoy::Event.create!(
      analytics_site: site,
      visit: visit,
      name: "engagement",
      properties: { page: "/pricing", engaged_ms: 1200 },
      time: 3.minutes.ago.change(usec: 0)
    )
    signup = Ahoy::Event.create!(
      analytics_site: site,
      visit: visit,
      name: "signup",
      properties: { page: "/docs" },
      time: 2.minutes.ago.change(usec: 0)
    )

    Analytics::VisitSummary.refresh_visit!(visit)
    pageview.destroy!
    engagement.destroy!
    signup.destroy!

    AnalyticsProfile::Projection.project_visit(visit)

    session = Analytics::VisitSummary.find_by!(visit_id: visit.id)
    assert_equal [ "pageview", "engagement", "signup" ], session.event_names
    assert_equal [ "/pricing", "/docs" ], session.page_paths
    assert_equal 1, session.pageviews_count
    assert_equal 3, session.events_count
    assert_equal 1200, session.engaged_ms_total if session.respond_to?(:engaged_ms_total)
  end

  test "project_visit builds summary aggregates across multiple sessions without loading summary shape regressions" do
    site, profile, first_visit = build_profile_with_visit(started_at: 8.minutes.ago.change(usec: 0))
    second_visit = Ahoy::Visit.create!(
      analytics_site: site,
      analytics_profile: profile,
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      browser_id: SecureRandom.uuid,
      started_at: 3.minutes.ago.change(usec: 0),
      country: "France",
      city: "Paris",
      device_type: "Mobile",
      browser: "Safari",
      os: "iOS",
      source_label: "Newsletter",
      landing_page: "https://docs.example.test/changelog"
    )

    Ahoy::Event.create!(
      analytics_site: site,
      visit: first_visit,
      name: "pageview",
      properties: { page: "/pricing" },
      time: 7.minutes.ago.change(usec: 0)
    )
    Ahoy::Event.create!(
      analytics_site: site,
      visit: second_visit,
      name: "pageview",
      properties: { page: "/pricing" },
      time: 2.minutes.ago.change(usec: 0)
    )
    Ahoy::Event.create!(
      analytics_site: site,
      visit: second_visit,
      name: "pageview",
      properties: { page: "/changelog" },
      time: 1.minute.ago.change(usec: 0)
    )

    AnalyticsProfile::Projection.project_visit(first_visit)
    AnalyticsProfile::Projection.project_visit(second_visit)

    summary = AnalyticsProfileSummary.find_by!(analytics_profile_id: profile.id)

    assert_equal 2, summary.total_sessions
    assert_equal 2, summary.total_visits
    assert_equal 3, summary.total_pageviews
    assert_equal "/changelog", summary.latest_current_page
    assert_equal({ "label" => "/pricing", "count" => 2 }, summary.top_pages.first)
    assert_equal [ "Desktop", "Mobile" ].sort, summary.devices_used.map { |item| item.fetch("label") }.sort
    assert_equal [ "Barcelona", "Paris" ].sort, summary.locations_used.map { |item| item.fetch("city") }.sort
  end
end
