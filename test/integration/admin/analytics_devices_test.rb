# frozen_string_literal: true

require "test_helper"

class Admin::AnalyticsDevicesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
  end

  test "devices endpoint returns real browser version rows with browser metadata" do
    staff_identity, = create_tenant(
      email: "staff-devices-browser-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Devices Browser"
    )
    staff_identity.update!(staff: true)

    Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      browser: "Chrome",
      browser_version: "135.0",
      started_at: Time.zone.now.change(usec: 0)
    )
    Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      browser: "Chrome",
      browser_version: "136.0",
      started_at: Time.zone.now.change(usec: 0)
    )

    sign_in(staff_identity)

    get "/admin/analytics/devices",
        params: { period: "day", mode: "browser-versions", with_imported: "false" },
        headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    rows = payload.fetch("results")
    assert_equal %w[visitors percentage bounce_rate visit_duration], payload.fetch("metrics")
    assert_equal [ "135.0", "136.0" ], rows.map { |row| row.fetch("name") }.sort
    assert_equal "Chrome", rows.find { |row| row.fetch("name") == "135.0" }.fetch("browser")
    assert_equal "Chrome", rows.find { |row| row.fetch("name") == "136.0" }.fetch("browser")
  ensure
    Current.reset
  end

  test "devices endpoint keeps same numeric version distinct across browsers" do
    staff_identity, = create_tenant(
      email: "staff-devices-distinct-versions-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Devices Distinct Versions"
    )
    staff_identity.update!(staff: true)

    Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "chrome-136",
      browser: "Chrome",
      browser_version: "136",
      started_at: Time.zone.now.change(usec: 0)
    )
    Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "firefox-136",
      browser: "Firefox",
      browser_version: "136",
      started_at: Time.zone.now.change(usec: 0)
    )

    sign_in(staff_identity)

    get "/admin/analytics/devices",
        params: { period: "day", mode: "browser-versions", with_imported: "false" },
        headers: { "ACCEPT" => "application/json" }

    assert_response :success

    rows = JSON.parse(response.body).fetch("results")
    assert_equal [ "Chrome 136", "Firefox 136" ], rows.map { |row| row.fetch("name") }.sort
    assert_equal "Chrome", rows.find { |row| row.fetch("name") == "Chrome 136" }.fetch("browser")
    assert_equal "Firefox", rows.find { |row| row.fetch("name") == "Firefox 136" }.fetch("browser")
  ensure
    Current.reset
  end

  test "devices endpoint applies browser version and os version filters" do
    staff_identity, = create_tenant(
      email: "staff-devices-version-filters-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Devices Version Filters"
    )
    staff_identity.update!(staff: true)

    Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "browser-version-a",
      browser: "Chrome",
      browser_version: "135.0",
      os: "macOS",
      os_version: "14.4",
      started_at: Time.zone.now.change(usec: 0)
    )
    Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "browser-version-b",
      browser: "Chrome",
      browser_version: "136.0",
      os: "macOS",
      os_version: "14.5",
      started_at: Time.zone.now.change(usec: 0)
    )

    sign_in(staff_identity)

    get "/admin/analytics/devices?period=day&mode=browser-versions&f=is,browser_version,136.0",
        headers: { "ACCEPT" => "application/json" }

    assert_response :success
    browser_rows = JSON.parse(response.body).fetch("results")
    assert_equal [ "136.0" ], browser_rows.map { |row| row.fetch("name") }

    get "/admin/analytics/devices?period=day&mode=operating-system-versions&f=is,os_version,14.4",
        headers: { "ACCEPT" => "application/json" }

    assert_response :success
    os_rows = JSON.parse(response.body).fetch("results")
    assert_equal [ "14.4" ], os_rows.map { |row| row.fetch("name") }
    assert_equal "macOS", os_rows.first.fetch("os")
  ensure
    Current.reset
  end
end
