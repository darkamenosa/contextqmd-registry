# frozen_string_literal: true

require "test_helper"

class Analytics::GoogleSearchConsole::SyncerTest < ActiveSupport::TestCase
  setup do
    Analytics::GoogleSearchConsole::QueryRow.delete_all
    Analytics::GoogleSearchConsole::Sync.delete_all
    Analytics::GoogleSearchConsoleConnection.delete_all
    Analytics::Site.delete_all
  end

  test "imports additive query facts and replaces existing range rows" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    connection = Analytics::GoogleSearchConsoleConnection.rotate_for_site!(
      site: site,
      attributes: {
        google_uid: "google-user-123",
        google_email: "owner@example.com",
        access_token: "access-token",
        refresh_token: "refresh-token",
        expires_at: 1.hour.from_now,
        scopes: Analytics::GoogleSearchConsole::Client::SCOPES,
        metadata: {},
        property_identifier: "sc-domain:example.test",
        property_type: "domain",
        permission_level: "siteOwner",
        last_verified_at: Time.current
      }
    )

    stale_sync = connection.syncs.create!(
      property_identifier: connection.property_identifier,
      search_type: "web",
      from_date: Date.new(2026, 3, 20),
      to_date: Date.new(2026, 3, 20),
      started_at: Time.current,
      finished_at: Time.current,
      status: Analytics::GoogleSearchConsole::Sync::STATUS_SUCCEEDED
    )
    Analytics::GoogleSearchConsole::QueryRow.create!(
      analytics_site: site,
      sync: stale_sync,
      date: Date.new(2026, 3, 20),
      search_type: "web",
      query: "stale query",
      page: "https://example.test/old",
      country: "USA",
      device: "desktop",
      clicks: 1,
      impressions: 2,
      position_impressions_sum: 4
    )

    fake_client = FakeGoogleSearchConsoleClient.new(
      rows_by_date: {
        Date.new(2026, 3, 20) => [
          {
            "keys" => [ "contextqmd analytics", "https://example.test/docs/install", "VNM", "DESKTOP" ],
            "clicks" => 10,
            "impressions" => 40,
            "position" => 2.5
          }
        ],
        Date.new(2026, 3, 21) => [
          {
            "keys" => [ "contextqmd analytics", "https://example.test/docs/install", "VNM", "DESKTOP" ],
            "clicks" => 5,
            "impressions" => 10,
            "position" => 3.0
          }
        ]
      }
    )

    sync = Analytics::GoogleSearchConsole::Syncer.new(
      connection: connection,
      from_date: Date.new(2026, 3, 20),
      to_date: Date.new(2026, 3, 21),
      client: fake_client
    ).perform!

    assert_equal Analytics::GoogleSearchConsole::Sync::STATUS_SUCCEEDED, sync.status
    assert_equal 2, Analytics::GoogleSearchConsole::QueryRow.for_site(site).count
    assert_equal false, Analytics::GoogleSearchConsole::QueryRow.for_site(site).exists?(query: "stale query")

    row = Analytics::GoogleSearchConsole::QueryRow.for_site(site).find_by!(date: Date.new(2026, 3, 20))
    assert_equal 10, row.clicks
    assert_equal 40, row.impressions
    assert_equal BigDecimal("100.0"), row.position_impressions_sum
    assert_equal "/docs/install", row.page
  end

  class FakeGoogleSearchConsoleClient
    def initialize(rows_by_date:)
      @rows_by_date = rows_by_date
    end

    def query_search_analytics(_access_token, start_date:, **)
      { "rows" => Array(@rows_by_date.fetch(start_date.to_date, [])) }
    end

    def refresh_access_token!(_refresh_token)
      {
        "access_token" => "refreshed-access-token",
        "expires_in" => 3600,
        "scope" => Analytics::GoogleSearchConsole::Client::SCOPES.join(" ")
      }
    end
  end
end
