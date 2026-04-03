# frozen_string_literal: true

require "test_helper"

class Analytics::SiteLocationHourlyVisitorRollupTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    Analytics::SiteLocationHourlyVisitorRollup.delete_all if Analytics::SiteLocationHourlyVisitorRollup.available?
    Ahoy::Visit.delete_all
    Analytics::SiteBoundary.delete_all
    Analytics::Site.delete_all
  end

  test "counts_for deduplicates the same visitor across hours and tracks dominant countries" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")

      Ahoy::Visit.create!(
        analytics_site: site,
        visit_token: SecureRandom.hex(16),
        visitor_token: "repeat-austin-visitor",
        region: "Texas",
        city: "Austin",
        country_code: "US",
        started_at: Time.zone.parse("2026-03-25 09:00:00")
      )
      Ahoy::Visit.create!(
        analytics_site: site,
        visit_token: SecureRandom.hex(16),
        visitor_token: "repeat-austin-visitor",
        region: "Texas",
        city: "Austin",
        country_code: "US",
        started_at: Time.zone.parse("2026-03-25 10:00:00")
      )
      Ahoy::Visit.create!(
        analytics_site: site,
        visit_token: SecureRandom.hex(16),
        visitor_token: "springfield-ca-1",
        region: "British Columbia",
        city: "Springfield",
        country_code: "CA",
        started_at: Time.zone.parse("2026-03-25 09:15:00")
      )
      Ahoy::Visit.create!(
        analytics_site: site,
        visit_token: SecureRandom.hex(16),
        visitor_token: "springfield-ca-2",
        region: "Ontario",
        city: "Springfield",
        country_code: "CA",
        started_at: Time.zone.parse("2026-03-25 10:15:00")
      )
      Ahoy::Visit.create!(
        analytics_site: site,
        visit_token: SecureRandom.hex(16),
        visitor_token: "springfield-us-1",
        region: "Illinois",
        city: "Springfield",
        country_code: "US",
        started_at: Time.zone.parse("2026-03-25 09:30:00")
      )

      range = Time.zone.parse("2026-03-25 09:00:00")..Time.zone.parse("2026-03-25 10:59:59")
      Analytics::SiteLocationHourlyVisitorRollup.refresh_range!(site: site, range: range)

      city_counts = Analytics::SiteLocationHourlyVisitorRollup.counts_for(
        range: range,
        site: site,
        dimension: "cities"
      )
      country_counts = Analytics::SiteLocationHourlyVisitorRollup.counts_for(
        range: range,
        site: site,
        dimension: "countries",
        search: "can"
      )
      dominant_country_codes = Analytics::SiteLocationHourlyVisitorRollup.dominant_country_codes_for(
        range: range,
        site: site,
        dimension: "cities",
        values: %w[Austin Springfield]
      )

      assert_equal 1, city_counts.fetch("Austin")
      assert_equal 3, city_counts.fetch("Springfield")
      assert_equal({ "CA" => 2 }, country_counts)
      assert_equal "US", dominant_country_codes.fetch("Austin")
      assert_equal "CA", dominant_country_codes.fetch("Springfield")
    end
  end

  test "usable_for stays false until every hourly bucket in range is refreshed" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")

      Ahoy::Visit.create!(
        analytics_site: site,
        visit_token: SecureRandom.hex(16),
        visitor_token: "austin-visitor",
        region: "Texas",
        city: "Austin",
        country_code: "US",
        started_at: Time.zone.parse("2026-03-25 09:00:00")
      )
      Ahoy::Visit.create!(
        analytics_site: site,
        visit_token: SecureRandom.hex(16),
        visitor_token: "seattle-visitor",
        region: "Washington",
        city: "Seattle",
        country_code: "US",
        started_at: Time.zone.parse("2026-03-25 10:00:00")
      )

      range = Time.zone.parse("2026-03-25 09:00:00")..Time.zone.parse("2026-03-25 10:59:59")

      Analytics::SiteVisitHourlyRollup.refresh_range!(site: site, range: range)
      Analytics::SiteLocationHourlyVisitorRollup.refresh_bucket!(site:, bucket_start: Time.zone.parse("2026-03-25 09:00:00"))

      assert_not Analytics::SiteLocationHourlyVisitorRollup.usable_for?(range:, site:, dimension: "cities")

      Analytics::SiteLocationHourlyVisitorRollup.refresh_bucket!(site:, bucket_start: Time.zone.parse("2026-03-25 10:00:00"))

      assert Analytics::SiteLocationHourlyVisitorRollup.usable_for?(range:, site:, dimension: "cities")
      assert_not Analytics::SiteLocationHourlyVisitorRollup.usable_for?(
        range: Time.zone.parse("2026-03-25 09:15:00")..Time.zone.parse("2026-03-25 10:45:00"),
        site: site,
        dimension: "cities"
      )
    end
  end
end
