# frozen_string_literal: true

require "test_helper"

class Analytics::SitePageHourlyRollupTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    Analytics::SitePageHourlyRollup.delete_all if Analytics::SitePageHourlyRollup.available?
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
    Analytics::SiteBoundary.delete_all
    Analytics::Site.delete_all
  end

  test "counts_for deduplicates visitors across hours while pageviews_for keeps summed totals" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")

      docs_first = Ahoy::Visit.create!(
        analytics_site: site,
        visit_token: SecureRandom.hex(16),
        visitor_token: "repeat-docs-visitor",
        started_at: Time.zone.parse("2026-03-25 09:00:00")
      )
      docs_second = Ahoy::Visit.create!(
        analytics_site: site,
        visit_token: SecureRandom.hex(16),
        visitor_token: "repeat-docs-visitor",
        started_at: Time.zone.parse("2026-03-25 10:00:00")
      )
      pricing_visit = Ahoy::Visit.create!(
        analytics_site: site,
        visit_token: SecureRandom.hex(16),
        visitor_token: "pricing-visitor",
        started_at: Time.zone.parse("2026-03-25 10:15:00")
      )

      [
        [ docs_first, "/docs", Time.zone.parse("2026-03-25 09:00:00") ],
        [ docs_first, "/docs", Time.zone.parse("2026-03-25 09:05:00") ],
        [ docs_second, "/docs", Time.zone.parse("2026-03-25 10:00:00") ],
        [ pricing_visit, "/pricing", Time.zone.parse("2026-03-25 10:15:00") ]
      ].each do |visit, page_path, at|
        Ahoy::Event.create!(
          visit: visit,
          analytics_site: site,
          name: "pageview",
          time: at,
          properties: { page: page_path }
        )
      end

      range = Time.zone.parse("2026-03-25 09:00:00")..Time.zone.parse("2026-03-25 10:59:59")
      Analytics::SitePageHourlyRollup.refresh_range!(site: site, range: range)

      counts = Analytics::SitePageHourlyRollup.counts_for(range: range, site: site)
      pageviews = Analytics::SitePageHourlyRollup.pageviews_for(range: range, site: site, search: "doc")

      assert_equal 1, counts.fetch("/docs")
      assert_equal 1, counts.fetch("/pricing")
      assert_equal({ "/docs" => 3 }, pageviews)
    end
  end

  test "usable_for stays false until every hourly bucket with pageviews is refreshed" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
      first_visit = Ahoy::Visit.create!(
        analytics_site: site,
        visit_token: SecureRandom.hex(16),
        visitor_token: "visitor-a",
        started_at: Time.zone.parse("2026-03-25 09:00:00")
      )
      second_visit = Ahoy::Visit.create!(
        analytics_site: site,
        visit_token: SecureRandom.hex(16),
        visitor_token: "visitor-b",
        started_at: Time.zone.parse("2026-03-25 10:00:00")
      )

      Ahoy::Event.create!(
        analytics_site: site,
        visit: first_visit,
        name: "pageview",
        time: Time.zone.parse("2026-03-25 09:10:00"),
        properties: { page: "/docs" }
      )
      Ahoy::Event.create!(
        analytics_site: site,
        visit: second_visit,
        name: "pageview",
        time: Time.zone.parse("2026-03-25 10:10:00"),
        properties: { page: "/pricing" }
      )

      range = Time.zone.parse("2026-03-25 09:00:00")..Time.zone.parse("2026-03-25 10:59:59")

      Analytics::SiteEventHourlyRollup.refresh_range!(site: site, range: range)
      Analytics::SitePageHourlyRollup.refresh_bucket!(site:, bucket_start: Time.zone.parse("2026-03-25 09:00:00"))

      assert_not Analytics::SitePageHourlyRollup.usable_for?(range:, site:)

      Analytics::SitePageHourlyRollup.refresh_bucket!(site:, bucket_start: Time.zone.parse("2026-03-25 10:00:00"))

      assert Analytics::SitePageHourlyRollup.usable_for?(range:, site:)
      assert_not Analytics::SitePageHourlyRollup.usable_for?(
        range: Time.zone.parse("2026-03-25 09:15:00")..Time.zone.parse("2026-03-25 10:45:00"),
        site: site
      )
    end
  end
end
