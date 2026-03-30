# frozen_string_literal: true

require "test_helper"

class Admin::AnalyticsPagesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
    Analytics::GoogleSearchConsole::QueryRow.delete_all
    Analytics::GoogleSearchConsole::Sync.delete_all
    Analytics::Setting.delete_all
    Analytics::Goal.delete_all
    Analytics::GoogleSearchConsoleConnection.delete_all
    Analytics::SiteBoundary.delete_all
    Analytics::Site.delete_all
  end

  test "site pages endpoint returns joined seo page metrics" do
    staff_identity, = create_tenant(
      email: "staff-analytics-pages-seo-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics Pages SEO"
    )
    staff_identity.update!(staff: true)

    site, _connection, sync = create_google_search_console_site!
    create_page_visit(site, visitor_token: "docs-1", at: 10.days.ago, path: "/docs/install")
    create_page_visit(site, visitor_token: "docs-2", at: 9.days.ago, path: "/docs/install")

    Analytics::GoogleSearchConsole::QueryRow.create!(
      analytics_site: site,
      sync: sync,
      date: 10.days.ago.to_date,
      search_type: "web",
      query: "contextqmd install",
      page: "https://docs.example.test/docs/install?ref=google",
      country: "VNM",
      device: "desktop",
      clicks: 40,
      impressions: 200,
      position_impressions_sum: 480
    )

    sign_in(staff_identity)

    get "/admin/analytics/sites/#{site.public_id}/pages",
      params: { period: "30d", mode: "seo" },
      headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    row = payload.fetch("results").find { |item| item.fetch("name") == "/docs/install" }

    assert_equal [ "clicks", "impressions", "ctr", "position", "visitors", "pageviews" ], payload.fetch("metrics")
    assert_equal false, payload.fetch("meta").fetch("searchConsole").fetch("unsupportedFilters")
    assert_equal true, payload.fetch("meta").fetch("searchConsole").fetch("configured")
    assert_equal(
      {
        "name" => "/docs/install",
        "clicks" => 40,
        "impressions" => 200,
        "ctr" => 20.0,
        "position" => 2.4,
        "visitors" => 2,
        "pageviews" => 2
      },
      row.slice("name", "clicks", "impressions", "ctr", "position", "visitors", "pageviews")
    )
  ensure
    Current.reset
  end

  test "site pages endpoint seo mode overlays goal conversions" do
    staff_identity, = create_tenant(
      email: "staff-analytics-pages-goal-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics Pages Goal"
    )
    staff_identity.update!(staff: true)

    site, _connection, sync = create_google_search_console_site!
    Analytics::Goal.create!(analytics_site: site, display_name: "Signup", event_name: "Signup", custom_props: {})

    converting_visit = create_page_visit(site, visitor_token: "docs-convert", at: 10.days.ago, path: "/docs/install")
    create_page_visit(site, visitor_token: "docs-other", at: 9.days.ago, path: "/docs/install")
    Ahoy::Event.create!(
      visit: converting_visit,
      analytics_site: site,
      name: "Signup",
      time: 10.days.ago + 5.minutes,
      properties: {}
    )

    Analytics::GoogleSearchConsole::QueryRow.create!(
      analytics_site: site,
      sync: sync,
      date: 10.days.ago.to_date,
      search_type: "web",
      query: "contextqmd install",
      page: "https://docs.example.test/docs/install",
      country: "VNM",
      device: "desktop",
      clicks: 12,
      impressions: 60,
      position_impressions_sum: 180
    )

    sign_in(staff_identity)

    get "/admin/analytics/sites/#{site.public_id}/pages",
      params: {
        period: "30d",
        mode: "seo",
        f: [ "is,goal,Signup" ]
      },
      headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    row = payload.fetch("results").find { |item| item.fetch("name") == "/docs/install" }

    assert_equal [ "clicks", "impressions", "ctr", "position", "visitors", "conversion_rate" ], payload.fetch("metrics")
    assert_equal "Conversions", payload.fetch("meta").fetch("metricLabels").fetch("visitors")
    assert_equal "Conversion Rate", payload.fetch("meta").fetch("metricLabels").fetch("conversionRate")
    assert_equal 1, row.fetch("visitors")
    assert_equal 50.0, row.fetch("conversionRate")
    assert_equal 12, row.fetch("clicks")
  ensure
    Current.reset
  end

  test "site pages endpoint seo mode flags unsupported filters" do
    staff_identity, = create_tenant(
      email: "staff-analytics-pages-unsupported-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics Pages Unsupported"
    )
    staff_identity.update!(staff: true)

    site, = create_google_search_console_site!

    sign_in(staff_identity)

    get "/admin/analytics/sites/#{site.public_id}/pages",
      params: {
        period: "30d",
        mode: "seo",
        f: [ "is,browser,Safari" ]
      },
      headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal [], payload.fetch("results")
    assert_equal true, payload.fetch("meta").fetch("searchConsole").fetch("unsupportedFilters")
  ensure
    Current.reset
  end

  test "site pages endpoint sorts top pages by percentage" do
    staff_identity, = create_tenant(
      email: "staff-analytics-pages-sort-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics Pages Sort"
    )
    staff_identity.update!(staff: true)

    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    create_page_visit(site, visitor_token: "docs-1", at: 10.days.ago, path: "/alpha")
    create_page_visit(site, visitor_token: "docs-2", at: 9.days.ago, path: "/alpha")
    create_page_visit(site, visitor_token: "docs-3", at: 8.days.ago, path: "/beta")

    sign_in(staff_identity)

    get "/admin/analytics/sites/#{site.public_id}/pages",
      params: {
        period: "30d",
        limit: 20,
        page: 1,
        order_by: [ [ "percentage", "asc" ] ].to_json
      },
      headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal [ "/beta", "/alpha" ], payload.fetch("results").map { |item| item.fetch("name") }
    assert_equal [ 0.333, 0.667 ], payload.fetch("results").map { |item| item.fetch("percentage") }
  ensure
    Current.reset
  end

  private
    def create_google_search_console_site!
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
        from_date: 30.days.ago.to_date,
        to_date: 3.days.ago.to_date,
        started_at: Time.current,
        finished_at: Time.current,
        status: Analytics::GoogleSearchConsole::Sync::STATUS_SUCCEEDED
      )

      [ site, connection, sync ]
    end

    def create_page_visit(site, visitor_token:, at:, path:)
      visit = Ahoy::Visit.create!(
        analytics_site: site,
        visit_token: SecureRandom.hex(16),
        visitor_token: visitor_token,
        started_at: at
      )

      Ahoy::Event.create!(
        visit: visit,
        analytics_site: site,
        name: "pageview",
        time: at,
        properties: { page: path }
      )

      visit
    end
end
