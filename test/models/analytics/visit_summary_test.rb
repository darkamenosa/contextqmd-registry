require "test_helper"

class Analytics::VisitSummaryTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    Analytics::VisitSummary.delete_all if Analytics::VisitSummary.available?
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
    Analytics::SiteBoundary.delete_all
    Analytics::Site.delete_all
  end

  test "refresh_visit builds entry and exit pages from pageviews" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
      visit = Ahoy::Visit.create!(
        analytics_site: site,
        visit_token: SecureRandom.hex(16),
        visitor_token: "summary-visitor",
        landing_page: "/internal/analytics",
        started_at: Time.zone.parse("2026-03-25 09:00:00")
      )

      Ahoy::Event.create!(
        visit: visit,
        analytics_site: site,
        name: "pageview",
        time: Time.zone.parse("2026-03-25 09:00:00"),
        properties: { page: "/pricing?utm=ad" }
      )
      Ahoy::Event.create!(
        visit: visit,
        analytics_site: site,
        name: "pageview",
        time: Time.zone.parse("2026-03-25 09:05:00"),
        properties: { page: "/docs" }
      )
      Ahoy::Event.create!(
        visit: visit,
        analytics_site: site,
        name: "Signup",
        time: Time.zone.parse("2026-03-25 09:06:00"),
        properties: {}
      )

      Analytics::VisitSummary.refresh_visit!(visit)
      summary = Analytics::VisitSummary.find_by!(visit_id: visit.id)

      assert_equal "/pricing", summary.entry_page
      assert_equal "/docs", summary.exit_page
      assert_equal "/docs", summary.current_page
      assert_equal 2, summary.pageviews_count
      assert_equal 300.0, summary.visit_duration_seconds
      assert_equal 360, summary.duration_seconds
      assert_equal true, summary.has_non_pageview_events
      assert_equal Time.zone.parse("2026-03-25 09:06:00"), summary.last_event_at
      assert_equal 3, summary.events_count
      assert_equal [ "pageview", "Signup" ], summary.event_names
      assert_equal [ "/pricing?utm=ad", "/docs" ], summary.page_paths
      assert_equal 0, summary.engaged_ms_total
    end
  end

  test "refresh_visit keeps projection fields for profile rebuilds when raw events disappear" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
      visit = Ahoy::Visit.create!(
        analytics_site: site,
        visit_token: SecureRandom.hex(16),
        visitor_token: "summary-projection",
        landing_page: "/pricing",
        started_at: Time.zone.parse("2026-03-25 09:00:00")
      )

      pageview = Ahoy::Event.create!(
        visit: visit,
        analytics_site: site,
        name: "pageview",
        time: Time.zone.parse("2026-03-25 09:00:00"),
        properties: { page: "/pricing" }
      )
      engagement = Ahoy::Event.create!(
        visit: visit,
        analytics_site: site,
        name: "engagement",
        time: Time.zone.parse("2026-03-25 09:01:00"),
        properties: { page: "/pricing", engaged_ms: 2400 }
      )
      signup = Ahoy::Event.create!(
        visit: visit,
        analytics_site: site,
        name: "signup",
        time: Time.zone.parse("2026-03-25 09:02:00"),
        properties: { page: "/docs" }
      )

      Analytics::VisitSummary.refresh_visit!(visit)
      pageview.destroy!
      engagement.destroy!
      signup.destroy!

      projection = Analytics::VisitSummary.projection_for_visit(visit)

      assert_equal [ "pageview", "engagement", "signup" ], projection[:event_names]
      assert_equal [ "/pricing", "/docs" ], projection[:page_paths]
      assert_equal 1, projection[:pageviews_count]
      assert_equal 3, projection[:events_count]
      assert_equal 2400, projection[:engaged_ms_total]
      assert_equal Time.zone.parse("2026-03-25 09:02:00"), projection[:last_event_at]
    end
  end

  test "refresh_visit keeps visits without usable entry pages out of entry groupings" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
      visit = Ahoy::Visit.create!(
        analytics_site: site,
        visit_token: SecureRandom.hex(16),
        visitor_token: "summary-no-pageviews",
        landing_page: "/a/e",
        started_at: Time.zone.parse("2026-03-25 09:00:00")
      )

      Analytics::VisitSummary.refresh_visit!(visit)
      summary = Analytics::VisitSummary.find_by!(visit_id: visit.id)

      assert_equal "", summary.entry_page
      assert_equal "", summary.exit_page
      assert_equal "", summary.current_page
      assert_equal 0, summary.pageviews_count
      assert_equal 0.0, summary.visit_duration_seconds
      assert_equal 0, summary.duration_seconds
      assert_equal false, summary.has_non_pageview_events
    end
  end
end
