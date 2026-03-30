# frozen_string_literal: true

require "test_helper"

class AnalyticsEmbedTest < ActionDispatch::IntegrationTest
  MODERN_BROWSER_HEADERS = {
    "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36"
  }.freeze

  setup do
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
    Analytics::SiteBoundary.delete_all
    Analytics::Site.delete_all
  end

  test "public tracker loader exposes the vite analytics entrypoint" do
    host! "localhost"

    get "/js/script.js", headers: MODERN_BROWSER_HEADERS

    assert_response :success
    assert_equal "application/javascript; charset=utf-8", response.media_type + "; charset=#{response.charset}"
    assert_includes response.body, "window.analyticsConfig"
    assert_includes response.body, "__analyticsModuleRequested"
    assert_includes response.body, "http://localhost/vite"
  ensure
    host! "www.example.com"
  end

  test "ahoy events preflight responds with tracker cors headers" do
    options "/ahoy/events", headers: { "Origin" => "https://docs.example.test" }

    assert_response :no_content
    assert_equal "*", response.headers["Access-Control-Allow-Origin"]
    assert_equal "POST, OPTIONS", response.headers["Access-Control-Allow-Methods"]
    assert_includes response.headers["Access-Control-Allow-Headers"], "Content-Type"
  end

  test "cross-origin event responses include tracker cors headers" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    token = Analytics::TrackerSiteToken.generate(
      site: site,
      mode: "external",
      expires_in: 180.days
    )

    host! "localhost"

    assert_difference -> { Ahoy::Event.count }, +1 do
      post "/ahoy/events",
        params: {
          events: [
            {
              name: "pageview",
              site_token: token,
              properties: {
                page: "/",
                url: "https://docs.example.test/",
                title: "Docs",
                referrer: "",
                screen_size: "1440x900"
              },
              time: Time.current.iso8601
            }
          ]
        },
        as: :json,
        headers: {
          "Origin" => "https://docs.example.test",
          "HTTP_USER_AGENT" => MODERN_BROWSER_HEADERS.fetch("HTTP_USER_AGENT"),
          "REMOTE_ADDR" => "203.0.113.42"
        }
    end

    assert_response :success
    assert_equal "*", response.headers["Access-Control-Allow-Origin"]
    assert_equal site.id, Ahoy::Event.order(:id).last.analytics_site_id
  ensure
    host! "www.example.com"
  end
end
