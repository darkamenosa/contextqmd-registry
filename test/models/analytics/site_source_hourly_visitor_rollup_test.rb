# frozen_string_literal: true

require "test_helper"

class Analytics::SiteSourceHourlyVisitorRollupTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    Analytics::SiteSourceHourlyVisitorRollup.delete_all if Analytics::SiteSourceHourlyVisitorRollup.available?
    Ahoy::Visit.delete_all
    Analytics::SiteBoundary.delete_all
    Analytics::Site.delete_all
  end

  test "counts_for deduplicates the same visitor across hours in a range" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")

      Ahoy::Visit.create!(
        analytics_site: site,
        visit_token: SecureRandom.hex(16),
        visitor_token: "repeat-google-visitor",
        referring_domain: "google.com",
        started_at: Time.zone.parse("2026-03-25 09:00:00")
      )
      Ahoy::Visit.create!(
        analytics_site: site,
        visit_token: SecureRandom.hex(16),
        visitor_token: "repeat-google-visitor",
        referring_domain: "google.com",
        started_at: Time.zone.parse("2026-03-25 10:00:00")
      )

      range = Time.zone.parse("2026-03-25 09:00:00")..Time.zone.parse("2026-03-25 10:59:59")
      Analytics::SiteSourceHourlyVisitorRollup.refresh_range!(site: site, range: range)

      counts = Analytics::SiteSourceHourlyVisitorRollup.counts_for(range: range, site: site, dimension: "all")

      assert_equal 1, counts.fetch("Google")
    end
  end

  test "usable_for stays false until every hourly bucket in range is refreshed" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")

      Ahoy::Visit.create!(
        analytics_site: site,
        visit_token: SecureRandom.hex(16),
        visitor_token: "first-google-visitor",
        referring_domain: "google.com",
        started_at: Time.zone.parse("2026-03-25 09:00:00")
      )
      Ahoy::Visit.create!(
        analytics_site: site,
        visit_token: SecureRandom.hex(16),
        visitor_token: "second-google-visitor",
        referring_domain: "google.com",
        started_at: Time.zone.parse("2026-03-25 10:00:00")
      )

      range = Time.zone.parse("2026-03-25 09:00:00")..Time.zone.parse("2026-03-25 10:59:59")

      Analytics::SiteVisitHourlyRollup.refresh_range!(site: site, range: range)
      Analytics::SiteSourceHourlyVisitorRollup.refresh_bucket!(site:, bucket_start: Time.zone.parse("2026-03-25 09:00:00"))

      assert_not Analytics::SiteSourceHourlyVisitorRollup.usable_for?(range:, site:, dimension: "all")

      Analytics::SiteSourceHourlyVisitorRollup.refresh_bucket!(site:, bucket_start: Time.zone.parse("2026-03-25 10:00:00"))

      assert Analytics::SiteSourceHourlyVisitorRollup.usable_for?(range:, site:, dimension: "all")
      assert_not Analytics::SiteSourceHourlyVisitorRollup.usable_for?(
        range: Time.zone.parse("2026-03-25 09:15:00")..Time.zone.parse("2026-03-25 10:45:00"),
        site: site,
        dimension: "all"
      )
    end
  end
end
