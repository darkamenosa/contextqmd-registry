# frozen_string_literal: true

require "test_helper"

class Analytics::GoogleSearchConsole::SearchTermsPreviewTest < ActiveSupport::TestCase
  setup do
    Analytics::GoogleSearchConsole::QueryRow.delete_all
    Analytics::GoogleSearchConsole::Sync.delete_all
    Analytics::GoogleSearchConsoleConnection.delete_all
    Analytics::Site.delete_all
    Ahoy::Visit.delete_all
  end

  test "derives likely queries from cached rows with progressive fallback" do
    site, sync = create_site_and_sync!
    visit = Ahoy::Visit.create!(
      analytics_site: site,
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      started_at: Time.zone.parse("2026-03-20 09:00:00"),
      country: "Czechia",
      device_type: "Desktop",
      referrer: "https://www.google.com/search?q=wrong+query",
      referring_domain: "google.com",
      utm_source: "google",
      utm_medium: "organic",
      landing_page: "https://docs.example.test/docs/install?ref=abc"
    )

    Analytics::GoogleSearchConsole::QueryRow.create!(
      analytics_site: site,
      sync: sync,
      date: Date.new(2026, 3, 20),
      search_type: "web",
      query: "contextqmd analytics",
      page: "https://docs.example.test/docs/install",
      country: "USA",
      device: "mobile",
      clicks: 21,
      impressions: 50,
      position_impressions_sum: 120
    )
    Analytics::GoogleSearchConsole::QueryRow.create!(
      analytics_site: site,
      sync: sync,
      date: Date.new(2026, 3, 20),
      search_type: "web",
      query: "analytics",
      page: "https://docs.example.test/docs/install",
      country: "USA",
      device: "mobile",
      clicks: 9,
      impressions: 30,
      position_impressions_sum: 75
    )
    Analytics::GoogleSearchConsole::QueryRow.create!(
      analytics_site: site,
      sync: sync,
      date: Date.new(2026, 3, 20),
      search_type: "web",
      query: "wrong page query",
      page: "https://docs.example.test/docs/other",
      country: "USA",
      device: "mobile",
      clicks: 100,
      impressions: 100,
      position_impressions_sum: 100
    )

    results = Analytics::GoogleSearchConsole::SearchTermsPreview.for_visit(visit)

    assert_equal "/docs/install", Analytics::GoogleSearchConsole::QueryRow.find_by!(query: "contextqmd analytics").page
    assert_equal [ "contextqmd analytics", "analytics" ], results.map { |row| row.fetch("label") }
    assert_equal 70, results.first.fetch("probability")
    assert_equal 30, results.second.fetch("probability")
  end

  test "returns no preview for non-organic google visits" do
    site, _sync = create_site_and_sync!
    visit = Ahoy::Visit.create!(
      analytics_site: site,
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      started_at: Time.zone.parse("2026-03-20 09:00:00"),
      country: "Czechia",
      device_type: "Desktop",
      utm_source: "google-ads",
      utm_medium: "cpc",
      landing_page: "https://docs.example.test/docs/install"
    )

    assert_equal [], Analytics::GoogleSearchConsole::SearchTermsPreview.for_visit(visit)
  end

  private
    def create_site_and_sync!
      site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
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
        from_date: Date.new(2026, 3, 20),
        to_date: Date.new(2026, 3, 20),
        started_at: Time.current,
        finished_at: Time.current,
        status: Analytics::GoogleSearchConsole::Sync::STATUS_SUCCEEDED
      )

      [ site, sync ]
    end
end
