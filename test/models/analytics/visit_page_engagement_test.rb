# frozen_string_literal: true

require "test_helper"

class Analytics::VisitPageEngagementTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    Analytics::VisitPageEngagement.delete_all if Analytics::VisitPageEngagement.available?
    Analytics::VisitSummary.delete_all if Analytics::VisitSummary.available?
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
    Analytics::SiteBoundary.delete_all
    Analytics::Site.delete_all
  end

  test "refresh_visit builds page metrics from pageviews and engagement" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
      visit = Ahoy::Visit.create!(
        analytics_site: site,
        visit_token: SecureRandom.hex(16),
        visitor_token: "engagement-visitor",
        started_at: Time.zone.parse("2026-03-25 09:00:00")
      )

      Ahoy::Event.create!(
        visit: visit,
        analytics_site: site,
        name: "pageview",
        time: Time.zone.parse("2026-03-25 09:00:00"),
        properties: { page: "/docs" }
      )
      Ahoy::Event.create!(
        visit: visit,
        analytics_site: site,
        name: "pageview",
        time: Time.zone.parse("2026-03-25 09:05:00"),
        properties: { page: "/pricing" }
      )
      Ahoy::Event.create!(
        visit: visit,
        analytics_site: site,
        name: "engagement",
        time: Time.zone.parse("2026-03-25 09:01:00"),
        properties: { page: "/docs", engaged_ms: 12_000, scroll_depth: 75 }
      )

      Analytics::VisitPageEngagement.refresh_visit!(visit)

      docs = Analytics::VisitPageEngagement.find_by!(visit_id: visit.id, page_path: "/docs")
      pricing = Analytics::VisitPageEngagement.find_by!(visit_id: visit.id, page_path: "/pricing")

      assert_equal 1, docs.pageviews_count
      assert_equal 0.0, docs.legacy_time_on_page_seconds
      assert_equal 0, docs.legacy_time_on_page_count
      assert_equal 12.0, docs.engaged_seconds_total
      assert docs.has_engagement
      assert_equal 75.0, docs.max_scroll_depth

      assert_equal 1, pricing.pageviews_count
      assert_equal 0.0, pricing.legacy_time_on_page_seconds
      assert_equal 0, pricing.legacy_time_on_page_count
      refute pricing.has_engagement
    end
  end

  test "pages metrics use the projection when engagement rows are gone" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
      visit = Ahoy::Visit.create!(
        analytics_site: site,
        visit_token: SecureRandom.hex(16),
        visitor_token: "projected-pages-visitor",
        started_at: Time.zone.parse("2026-03-25 09:00:00")
      )

      pageview = Ahoy::Event.create!(
        visit: visit,
        analytics_site: site,
        name: "pageview",
        time: Time.zone.parse("2026-03-25 09:00:00"),
        properties: { page: "/docs" }
      )
      Ahoy::Event.create!(
        visit: visit,
        analytics_site: site,
        name: "pageview",
        time: Time.zone.parse("2026-03-25 09:10:00"),
        properties: { page: "/pricing" }
      )
      engagement = Ahoy::Event.create!(
        visit: visit,
        analytics_site: site,
        name: "engagement",
        time: Time.zone.parse("2026-03-25 09:01:00"),
        properties: { page: "/docs", engaged_ms: 12_000, scroll_depth: 75 }
      )

      Analytics::VisitPageEngagement.refresh_visit!(visit)
      pageview.touch
      engagement.destroy!

      metrics = Analytics::Pages.time_on_page_and_scroll(
        Time.zone.parse("2026-03-25 00:00:00")..Time.zone.parse("2026-03-25 23:59:59"),
        Analytics::Query.new(filters: {}),
        { "/docs" => [ visit.id ] }
      )

      assert_equal 12.0, metrics.dig("/docs", :time_on_page)
      assert_equal 75, metrics.dig("/docs", :scroll_depth)
    end
  end

  test "page filter metrics use the projection when engagement rows are gone" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
      visit = Ahoy::Visit.create!(
        analytics_site: site,
        visit_token: SecureRandom.hex(16),
        visitor_token: "projected-page-filter-visitor",
        landing_page: "/docs",
        started_at: Time.zone.parse("2026-03-25 09:00:00")
      )

      Ahoy::Event.create!(
        visit: visit,
        analytics_site: site,
        name: "pageview",
        time: Time.zone.parse("2026-03-25 09:00:00"),
        properties: { page: "/docs" }
      )
      Ahoy::Event.create!(
        visit: visit,
        analytics_site: site,
        name: "pageview",
        time: Time.zone.parse("2026-03-25 09:10:00"),
        properties: { page: "/pricing" }
      )
      engagement = Ahoy::Event.create!(
        visit: visit,
        analytics_site: site,
        name: "engagement",
        time: Time.zone.parse("2026-03-25 09:01:00"),
        properties: { page: "/docs", engaged_ms: 12_000, scroll_depth: 75 }
      )

      Analytics::VisitPageEngagement.refresh_visit!(visit)
      Analytics::VisitSummary.refresh_visit!(visit)
      engagement.destroy!

      metrics = Analytics::ReportMetrics.page_filter_metrics(
        Time.zone.parse("2026-03-25 00:00:00")..Time.zone.parse("2026-03-25 23:59:59"),
        Analytics::Query.new(filters: { page: "/docs" })
      )

      assert_equal 1, metrics[:visitors]
      assert_equal 1, metrics[:visits]
      assert_equal 1, metrics[:pageviews]
      assert_equal 0.0, metrics[:bounce_rate]
      assert_equal 12.0, metrics[:time_on_page]
      assert_equal 75.0, metrics[:scroll_depth]
    end
  end
end
