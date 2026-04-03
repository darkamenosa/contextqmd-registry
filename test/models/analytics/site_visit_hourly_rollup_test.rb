# frozen_string_literal: true

require "test_helper"

class Analytics::SiteVisitHourlyRollupTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    Analytics::SiteVisitHourlyRollup.delete_all if Analytics::SiteVisitHourlyRollup.available?
    Analytics::VisitSummary.delete_all if Analytics::VisitSummary.available?
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
    Analytics::SiteBoundary.delete_all
    Analytics::Site.delete_all
  end

  test "usable_for stays false until every full bucket in range is refreshed" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")

      create_visit(site:, visitor_token: "a", started_at: Time.zone.parse("2026-03-25 09:10:00"))
      create_visit(site:, visitor_token: "b", started_at: Time.zone.parse("2026-03-25 10:10:00"))

      range = Time.zone.parse("2026-03-25 09:00:00")..Time.zone.parse("2026-03-25 10:59:59")
      Analytics::SiteVisitHourlyRollup.refresh_bucket!(site:, bucket_start: Time.zone.parse("2026-03-25 09:00:00"))

      assert_not Analytics::SiteVisitHourlyRollup.usable_for?(range:, site:)

      Analytics::SiteVisitHourlyRollup.refresh_bucket!(site:, bucket_start: Time.zone.parse("2026-03-25 10:00:00"))

      assert Analytics::SiteVisitHourlyRollup.usable_for?(range:, site:)
    end
  end

  test "sum_for and series_for trim partial edge hours exactly" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")

      create_visit(site:, visitor_token: "edge-early", started_at: Time.zone.parse("2026-03-25 09:10:00"))
      create_visit(site:, visitor_token: "edge-late", started_at: Time.zone.parse("2026-03-25 09:50:00"))
      create_visit(site:, visitor_token: "middle-a", started_at: Time.zone.parse("2026-03-25 10:10:00"))
      create_visit(site:, visitor_token: "middle-b", started_at: Time.zone.parse("2026-03-25 10:50:00"))
      create_visit(site:, visitor_token: "edge-end", started_at: Time.zone.parse("2026-03-25 11:10:00"))

      Analytics::SiteVisitHourlyRollup.refresh_range!(
        site: site,
        range: Time.zone.parse("2026-03-25 09:00:00")..Time.zone.parse("2026-03-25 11:59:59")
      )

      range = Time.zone.parse("2026-03-25 09:30:00")..Time.zone.parse("2026-03-25 11:30:00")

      assert_equal 4, Analytics::SiteVisitHourlyRollup.sum_for(range:, site:, column: :visits_count)

      series = Analytics::SiteVisitHourlyRollup.series_for(range:, interval: "hour", site:, column: :visits_count)

      assert_equal 1, series.fetch(Time.zone.parse("2026-03-25 09:00:00").utc)
      assert_equal 2, series.fetch(Time.zone.parse("2026-03-25 10:00:00").utc)
      assert_equal 1, series.fetch(Time.zone.parse("2026-03-25 11:00:00").utc)
    end
  end

  private
    def create_visit(site:, visitor_token:, started_at:)
      Ahoy::Visit.create!(
        analytics_site: site,
        visit_token: SecureRandom.hex(16),
        visitor_token: visitor_token,
        started_at: started_at
      )
    end
end
