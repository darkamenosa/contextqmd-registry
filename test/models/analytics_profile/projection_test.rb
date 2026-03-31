# frozen_string_literal: true

require "test_helper"

class AnalyticsProfileProjectionTest < ActiveSupport::TestCase
  setup do
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
    AnalyticsProfileSession.delete_all if defined?(AnalyticsProfileSession)
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

    AnalyticsProfileSession.create!(
      visit: visit,
      analytics_profile: profile,
      analytics_site: site,
      started_at: visit.started_at,
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

    session = AnalyticsProfileSession.find_by!(visit_id: visit.id)
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

    assert_equal 1, AnalyticsProfileSession.where(visit_id: visit.id).count
    assert_equal 1, AnalyticsProfileSummary.where(analytics_profile_id: profile.id).count

    session = AnalyticsProfileSession.find_by!(visit_id: visit.id)
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
    assert_equal 1, AnalyticsProfileSession.where(visit_id: visit.id).count
    assert_equal 1, AnalyticsProfileSummary.where(analytics_profile_id: profile.id).count

    visit.update_columns(analytics_profile_id: nil)

    AnalyticsProfile::Projection.project_visit(visit, previous_profile_id: profile.id)

    assert_equal 0, AnalyticsProfileSession.where(visit_id: visit.id).count
    assert_equal 0, AnalyticsProfileSummary.where(analytics_profile_id: profile.id).count
  end
end
