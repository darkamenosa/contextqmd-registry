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

  test "public tracker loader is the canonical analytics delivery path" do
    host! "localhost"

    get "/analytics/script.js", headers: MODERN_BROWSER_HEADERS

    assert_response :success
    assert_equal "text/javascript; charset=utf-8", response.media_type + "; charset=#{response.charset}"
    assert_includes response.body, "window.analyticsConfig"
    assert_includes response.body, "window.analytics ="
    assert_includes response.body, "__analyticsModuleRequested"
    assert_includes response.body, "/analytics/bootstrap"
    assert_includes response.body, "http://localhost/vite"
  ensure
    host! "www.example.com"
  end

  test "public tracker loader responds with 304 when the etag matches" do
    host! "localhost"

    get "/analytics/script.js", headers: MODERN_BROWSER_HEADERS

    assert_response :success
    etag = response.headers["ETag"]
    assert etag.present?

    get "/analytics/script.js", headers: MODERN_BROWSER_HEADERS.merge("If-None-Match" => etag)

    assert_response :not_modified
    assert_empty response.body
  ensure
    host! "www.example.com"
  end

  test "public tracker bootstrap mints runtime config for a matching embed origin" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")

    host! "localhost"

    post "/analytics/bootstrap",
      params: { website_id: site.public_id },
      as: :json,
      headers: {
        "Origin" => "https://docs.example.test",
        "Referer" => "https://docs.example.test/blog/how-plausible-works"
      }

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal site.public_id, payload.dig("site", "websiteId")
    assert_equal "http://localhost/analytics/events", payload.dig("transport", "eventsEndpoint")
    assert payload.dig("site", "token").present?
  ensure
    host! "www.example.com"
  end

  test "public tracker bootstrap rejects website ids for a different embed origin" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    Analytics::Site.create!(name: "Blog", canonical_hostname: "blog.example.test")

    host! "localhost"

    post "/analytics/bootstrap",
      params: { website_id: site.public_id },
      as: :json,
      headers: {
        "Origin" => "https://other.example.test",
        "Referer" => "https://other.example.test/path"
      }

    assert_response :forbidden
  ensure
    host! "www.example.com"
  end

  test "public tracker bootstrap rejects pages outside the site's path boundary" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "example.test")
    site.boundaries.find_by(primary: true)&.destroy!
    Analytics::SiteBoundary.create!(site: site, host: "example.test", path_prefix: "/blog", primary: false, priority: 0)

    host! "localhost"

    post "/analytics/bootstrap",
      params: { website_id: site.public_id },
      as: :json,
      headers: {
        "Origin" => "https://example.test",
        "Referer" => "https://example.test/shop"
      }

    assert_response :forbidden
  ensure
    host! "www.example.com"
  end

  test "ahoy events preflight responds with tracker cors headers" do
    options "/analytics/events", headers: { "Origin" => "https://docs.example.test" }

    assert_response :no_content
    assert_equal "*", response.headers["Access-Control-Allow-Origin"]
    assert_equal "POST, OPTIONS", response.headers["Access-Control-Allow-Methods"]
    assert_includes response.headers["Access-Control-Allow-Headers"], "Content-Type"
  end

  test "bootstrap preflight responds with tracker cors headers" do
    options "/analytics/bootstrap", headers: { "Origin" => "https://docs.example.test" }

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
      post "/analytics/events",
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

  test "cross-origin events reject an invalid site token instead of creating unscoped rows" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    token = Analytics::TrackerSiteToken.generate(
      site: site,
      mode: "external",
      expires_in: 180.days
    )

    host! "localhost"

    assert_no_difference -> { Ahoy::Visit.count } do
      assert_no_difference -> { Ahoy::Event.count } do
        post "/analytics/events",
          params: {
            events: [
              {
                name: "pageview",
                site_token: token,
                properties: {
                  page: "/",
                  url: "https://other.example.test/",
                  title: "Other",
                  referrer: "",
                  screen_size: "1440x900"
                },
                time: Time.current.iso8601
              }
            ]
          },
          as: :json,
          headers: {
            "Origin" => "https://other.example.test",
            "HTTP_USER_AGENT" => MODERN_BROWSER_HEADERS.fetch("HTTP_USER_AGENT"),
            "REMOTE_ADDR" => "203.0.113.42"
          }
      end
    end

    assert_response :success
  ensure
    host! "www.example.com"
  end
end
