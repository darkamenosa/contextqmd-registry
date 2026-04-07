# frozen_string_literal: true

require "test_helper"

class Admin::AnalyticsSearchTermsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Analytics::GoogleSearchConsole::QueryRow.delete_all
    Analytics::GoogleSearchConsole::Sync.delete_all
    Analytics::GoogleSearchConsoleConnection.delete_all
    Analytics::SiteBoundary.delete_all
    Analytics::Site.delete_all
  end

  test "site search terms endpoint reads cached search console metrics" do
    staff_identity, = create_tenant(
      email: "staff-analytics-search-terms-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics Search Terms"
    )
    staff_identity.update!(staff: true)

    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    connection = Analytics::GoogleSearchConsoleConnection.rotate_for_site!(
      site: site,
      attributes: {
        google_uid: "google-user-789",
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
    sync = connection.syncs.create!(
      property_identifier: connection.property_identifier,
      search_type: "web",
      from_date: 30.days.ago.to_date,
      to_date: 3.days.ago.to_date,
      started_at: Time.current,
      finished_at: Time.current,
      status: Analytics::GoogleSearchConsole::Sync::STATUS_SUCCEEDED
    )
    Analytics::GoogleSearchConsole::QueryRow.create!(
      analytics_site: site,
      sync: sync,
      date: 10.days.ago.to_date,
      search_type: "web",
      query: "contextqmd analytics",
      page: "https://docs.example.test/docs/install",
      country: "VNM",
      device: "desktop",
      clicks: 25,
      impressions: 100,
      position_impressions_sum: 320
    )
    Analytics::GoogleSearchConsole::QueryRow.create!(
      analytics_site: site,
      sync: sync,
      date: 10.days.ago.to_date,
      search_type: "web",
      query: "rails docs",
      page: "https://docs.example.test/docs/install",
      country: "VNM",
      device: "desktop",
      clicks: 12,
      impressions: 80,
      position_impressions_sum: 432
    )

    sign_in(staff_identity)

    get "/admin/analytics/sites/#{site.public_id}/search_terms",
      params: {
        period: "28d",
        f: [
          "is,source,Google",
          "is,page,/docs/install",
          "is,country,VN"
        ]
      },
      headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal [ "visitors", "impressions", "ctr", "position" ], payload.fetch("metrics")
    assert_equal "Visitors", payload.fetch("meta").fetch("metricLabels").fetch("visitors")
    assert_equal false, payload.fetch("meta").fetch("searchConsole").fetch("syncInProgress")
    assert_equal false, payload.fetch("meta").fetch("searchConsole").fetch("syncStale")
    assert_equal(
      {
        "name" => "contextqmd analytics",
        "visitors" => 25,
        "impressions" => 100,
        "ctr" => 25.0,
        "position" => 3.2
      },
      payload.fetch("results").first.slice("name", "visitors", "impressions", "ctr", "position")
    )
  ensure
    Current.reset
  end

  test "site search terms endpoint syncs missing cached rows on demand" do
    staff_identity, = create_tenant(
      email: "staff-analytics-search-terms-sync-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics Search Terms Sync"
    )
    staff_identity.update!(staff: true)

    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    connection = Analytics::GoogleSearchConsoleConnection.rotate_for_site!(
      site: site,
      attributes: {
        google_uid: "google-user-789",
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
    sync_date = 10.days.ago.to_date
    fake_client = FakeGoogleSearchConsoleClient.new(
      rows_by_date: {
        sync_date => [
          {
            "keys" => [ "contextqmd analytics", "https://docs.example.test/docs/install", "VNM", "DESKTOP" ],
            "clicks" => 25,
            "impressions" => 100,
            "position" => 3.2
          }
        ]
      }
    )

    sign_in(staff_identity)

    with_google_search_console_client(fake_client) do
      get "/admin/analytics/sites/#{site.public_id}/search_terms",
        params: {
          period: "custom",
          from: sync_date.iso8601,
          to: sync_date.iso8601,
          f: [ "is,source,Google", "is,page,/docs/install", "is,country,VN" ]
        },
        headers: { "ACCEPT" => "application/json" }
    end

    assert_response :success
    assert_equal 1, Analytics::GoogleSearchConsole::QueryRow.for_site(site).count
    assert_equal "sc-domain:example.test", fake_client.last_query_request.fetch(:property_identifier)
    assert_equal sync_date, Analytics::GoogleSearchConsole::QueryRow.for_site(site).pick(:date)
  ensure
    Current.reset
  end

  test "site search terms endpoint merges repeated query rows into one visitor total" do
    staff_identity, = create_tenant(
      email: "staff-analytics-search-terms-merge-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics Search Terms Merge"
    )
    staff_identity.update!(staff: true)

    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    connection = Analytics::GoogleSearchConsoleConnection.rotate_for_site!(
      site: site,
      attributes: {
        google_uid: "google-user-merge",
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
    sync = connection.syncs.create!(
      property_identifier: connection.property_identifier,
      search_type: "web",
      from_date: 30.days.ago.to_date,
      to_date: 3.days.ago.to_date,
      started_at: Time.current,
      finished_at: Time.current,
      status: Analytics::GoogleSearchConsole::Sync::STATUS_SUCCEEDED
    )

    Analytics::GoogleSearchConsole::QueryRow.create!(
      analytics_site: site,
      sync: sync,
      date: 10.days.ago.to_date,
      search_type: "web",
      query: "contextqmd analytics",
      page: "https://docs.example.test/docs/install",
      country: "VNM",
      device: "desktop",
      clicks: 25,
      impressions: 100,
      position_impressions_sum: 320
    )
    Analytics::GoogleSearchConsole::QueryRow.create!(
      analytics_site: site,
      sync: sync,
      date: 9.days.ago.to_date,
      search_type: "web",
      query: "contextqmd analytics",
      page: "https://docs.example.test/docs/install",
      country: "USA",
      device: "mobile",
      clicks: 5,
      impressions: 20,
      position_impressions_sum: 30
    )

    sign_in(staff_identity)

    get "/admin/analytics/sites/#{site.public_id}/search_terms",
      params: { period: "28d" },
      headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    row = payload.fetch("results").find { |item| item.fetch("name") == "contextqmd analytics" }

    assert_equal 30, row.fetch("visitors")
    assert_equal 120, row.fetch("impressions")
    assert_equal 25.0, row.fetch("ctr")
    assert_equal 2.9, row.fetch("position")
  ensure
    Current.reset
  end

  test "site search terms endpoint sorts merged rows by requested metric" do
    staff_identity, = create_tenant(
      email: "staff-analytics-search-terms-sort-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics Search Terms Sort"
    )
    staff_identity.update!(staff: true)

    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    connection = Analytics::GoogleSearchConsoleConnection.rotate_for_site!(
      site: site,
      attributes: {
        google_uid: "google-user-sort",
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
    sync = connection.syncs.create!(
      property_identifier: connection.property_identifier,
      search_type: "web",
      from_date: 30.days.ago.to_date,
      to_date: 3.days.ago.to_date,
      started_at: Time.current,
      finished_at: Time.current,
      status: Analytics::GoogleSearchConsole::Sync::STATUS_SUCCEEDED
    )

    Analytics::GoogleSearchConsole::QueryRow.create!(
      analytics_site: site,
      sync: sync,
      date: 10.days.ago.to_date,
      search_type: "web",
      query: "high impressions",
      page: "https://docs.example.test/docs/install",
      country: "VNM",
      device: "desktop",
      clicks: 10,
      impressions: 200,
      position_impressions_sum: 400
    )
    Analytics::GoogleSearchConsole::QueryRow.create!(
      analytics_site: site,
      sync: sync,
      date: 9.days.ago.to_date,
      search_type: "web",
      query: "high impressions",
      page: "https://docs.example.test/docs/install",
      country: "USA",
      device: "mobile",
      clicks: 5,
      impressions: 100,
      position_impressions_sum: 200
    )
    Analytics::GoogleSearchConsole::QueryRow.create!(
      analytics_site: site,
      sync: sync,
      date: 10.days.ago.to_date,
      search_type: "web",
      query: "low impressions",
      page: "https://docs.example.test/docs/install",
      country: "VNM",
      device: "desktop",
      clicks: 20,
      impressions: 20,
      position_impressions_sum: 20
    )

    sign_in(staff_identity)

    get "/admin/analytics/sites/#{site.public_id}/search_terms",
      params: {
        period: "28d",
        order_by: [ [ "impressions", "asc" ] ].to_json
      },
      headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal [ "low impressions", "high impressions" ], payload.fetch("results").map { |item| item.fetch("name") }
    assert_equal [ 20, 300 ], payload.fetch("results").map { |item| item.fetch("impressions") }
  ensure
    Current.reset
  end

  test "site search terms endpoint paginates merged rows with has_more" do
    staff_identity, = create_tenant(
      email: "staff-analytics-search-terms-pagination-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics Search Terms Pagination"
    )
    staff_identity.update!(staff: true)

    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    connection = Analytics::GoogleSearchConsoleConnection.rotate_for_site!(
      site: site,
      attributes: {
        google_uid: "google-user-pagination",
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
    sync = connection.syncs.create!(
      property_identifier: connection.property_identifier,
      search_type: "web",
      from_date: 30.days.ago.to_date,
      to_date: 3.days.ago.to_date,
      started_at: Time.current,
      finished_at: Time.current,
      status: Analytics::GoogleSearchConsole::Sync::STATUS_SUCCEEDED
    )

    [
      [ "alpha", 30, 100, 200 ],
      [ "beta", 20, 80, 120 ],
      [ "gamma", 10, 40, 80 ]
    ].each do |query_name, clicks, impressions, position_impressions_sum|
      Analytics::GoogleSearchConsole::QueryRow.create!(
        analytics_site: site,
        sync: sync,
        date: 10.days.ago.to_date,
        search_type: "web",
        query: query_name,
        page: "https://docs.example.test/docs/install",
        country: "VNM",
        device: "desktop",
        clicks: clicks,
        impressions: impressions,
        position_impressions_sum: position_impressions_sum
      )
    end

    sign_in(staff_identity)

    get "/admin/analytics/sites/#{site.public_id}/search_terms",
      params: { period: "28d", limit: 2, page: 1 },
      headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal [ "alpha", "beta" ], payload.fetch("results").map { |item| item.fetch("name") }
    assert_equal true, payload.fetch("meta").fetch("hasMore")

    get "/admin/analytics/sites/#{site.public_id}/search_terms",
      params: { period: "28d", limit: 2, page: 2 },
      headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal [ "gamma" ], payload.fetch("results").map { |item| item.fetch("name") }
    assert_equal false, payload.fetch("meta").fetch("hasMore")
  ensure
    Current.reset
  end

  test "search terms reject unsupported browser filters" do
    staff_identity, = create_tenant(
      email: "staff-analytics-search-terms-unsupported-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics Search Terms Unsupported"
    )
    staff_identity.update!(staff: true)

    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    Analytics::GoogleSearchConsoleConnection.rotate_for_site!(
      site: site,
      attributes: {
        google_uid: "google-user-987",
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

    sign_in(staff_identity)

    get "/admin/analytics/sites/#{site.public_id}/search_terms",
      params: {
        period: "28d",
        f: [ "is,browser,Safari" ]
      },
      headers: { "ACCEPT" => "application/json" }

    assert_response :unprocessable_entity
    assert_equal({ "errorCode" => "unsupported_filters" }, JSON.parse(response.body))
  ensure
    Current.reset
  end

  test "search terms return request_failed when refresh token is revoked" do
    staff_identity, = create_tenant(
      email: "staff-analytics-search-terms-refresh-failure-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics Search Terms Refresh Failure"
    )
    staff_identity.update!(staff: true)

    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    Analytics::GoogleSearchConsoleConnection.rotate_for_site!(
      site: site,
      attributes: {
        google_uid: "google-user-refresh-failure",
        google_email: "owner@example.com",
        access_token: "expired-access-token",
        refresh_token: "revoked-refresh-token",
        expires_at: 1.hour.ago,
        scopes: Analytics::GoogleSearchConsole::Client::SCOPES,
        metadata: {},
        property_identifier: "sc-domain:example.test",
        property_type: "domain",
        permission_level: "siteOwner",
        last_verified_at: Time.current
      }
    )

    sign_in(staff_identity)

    with_google_search_console_client(
      FakeGoogleSearchConsoleClient.new(
        rows_by_date: {},
        refresh_error: Analytics::GoogleSearchConsole::Client::Error.new(
          "Token has been expired or revoked.",
          reason: :reauth_required
        )
      )
    ) do
      get "/admin/analytics/sites/#{site.public_id}/search_terms",
        params: {
          period: "custom",
          from: 7.days.ago.to_date.iso8601,
          to: 7.days.ago.to_date.iso8601,
          f: [ "is,source,Google" ]
        },
        headers: { "ACCEPT" => "application/json" }
    end

    assert_response :unprocessable_entity
    assert_equal(
      {
        "errorCode" => "request_failed",
        "message" => "Token has been expired or revoked."
      },
      JSON.parse(response.body)
    )
    assert_equal Analytics::GoogleSearchConsoleConnection::STATUS_REVOKED, Analytics::GoogleSearchConsoleConnection.current_for(site)&.status
  ensure
    Current.reset
  end

  test "search terms stay readable from cached rows when google auth is revoked but coverage exists" do
    staff_identity, = create_tenant(
      email: "staff-analytics-search-terms-revoked-cache-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics Search Terms Revoked Cache"
    )
    staff_identity.update!(staff: true)

    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    connection = Analytics::GoogleSearchConsoleConnection.rotate_for_site!(
      site: site,
      attributes: {
        google_uid: "google-user-revoked-cache",
        google_email: "owner@example.com",
        access_token: "expired-access-token",
        refresh_token: "revoked-refresh-token",
        expires_at: 1.hour.ago,
        scopes: Analytics::GoogleSearchConsole::Client::SCOPES,
        metadata: {
          "connection_error" => "Token has been expired or revoked."
        },
        status: Analytics::GoogleSearchConsoleConnection::STATUS_REVOKED,
        property_identifier: "sc-domain:example.test",
        property_type: "domain",
        permission_level: "siteOwner",
        last_verified_at: Time.current
      }
    )
    cached_date = 7.days.ago.to_date
    sync = connection.syncs.create!(
      property_identifier: connection.property_identifier,
      search_type: "web",
      from_date: cached_date,
      to_date: cached_date,
      started_at: 10.minutes.ago,
      finished_at: 5.minutes.ago,
      status: Analytics::GoogleSearchConsole::Sync::STATUS_SUCCEEDED
    )
    Analytics::GoogleSearchConsole::QueryRow.create!(
      analytics_site: site,
      sync: sync,
      date: cached_date,
      search_type: "web",
      query: "contextqmd analytics",
      page: "/docs/install",
      country: "USA",
      device: "desktop",
      clicks: 12,
      impressions: 34,
      position_impressions_sum: 68
    )

    sign_in(staff_identity)

    get "/admin/analytics/sites/#{site.public_id}/search_terms",
      params: {
        period: "custom",
        from: cached_date.iso8601,
        to: cached_date.iso8601,
        f: [ "is,source,Google" ]
      },
      headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal 1, payload.fetch("results").length
    assert_equal true, payload.fetch("meta").fetch("searchConsole").fetch("reauthRequired")
    assert_equal "Token has been expired or revoked.", payload.fetch("meta").fetch("searchConsole").fetch("connectionError")
  ensure
    Current.reset
  end

  class FakeGoogleSearchConsoleClient
    attr_reader :last_query_request

    def initialize(rows_by_date:, refresh_error: nil)
      @rows_by_date = rows_by_date
      @last_query_request = nil
      @refresh_error = refresh_error
    end

    def query_search_analytics(access_token, start_date:, **kwargs)
      @last_query_request = kwargs.merge(access_token: access_token)
      { "rows" => Array(@rows_by_date.fetch(start_date.to_date, [])) }
    end

    def refresh_access_token!(_refresh_token)
      raise @refresh_error if @refresh_error.present?

      {
        "access_token" => "refreshed-access-token",
        "expires_in" => 3600,
        "scope" => Analytics::GoogleSearchConsole::Client::SCOPES.join(" ")
      }
    end
  end

  private
    def with_google_search_console_client(fake_client)
      original_new = Analytics::GoogleSearchConsole::Client.method(:new)
      Analytics::GoogleSearchConsole::Client.define_singleton_method(:new) do |*|
        fake_client
      end
      yield
    ensure
      Analytics::GoogleSearchConsole::Client.define_singleton_method(:new, original_new)
    end
end
