# frozen_string_literal: true

require "test_helper"

class SeoTest < ActionDispatch::IntegrationTest
  test "sitemap.xml returns valid XML with required URLs" do
    get "/sitemap.xml"
    assert_response :success
    assert_equal "application/xml; charset=utf-8", response.content_type
    assert_includes response.body, "<urlset"
    assert_includes response.body, "<loc>https://contextqmd.com/</loc>"
    assert_includes response.body, "<loc>https://contextqmd.com/libraries</loc>"
    assert_includes response.body, "<loc>https://contextqmd.com/rankings</loc>"
    assert_includes response.body, "<loc>https://contextqmd.com/about</loc>"
  end

  test "sitemap.xml includes library URLs" do
    lib = Library.first
    skip "No libraries in test DB" unless lib

    get "/sitemap.xml"
    assert_includes response.body, "<loc>https://contextqmd.com/libraries/#{lib.slug}</loc>"
  end

  test "robots.txt is served with sitemap directive" do
    get "/robots.txt"
    assert_response :success
    assert_includes response.body, "Sitemap: https://contextqmd.com/sitemap.xml"
    assert_includes response.body, "Disallow: /admin/"
    assert_includes response.body, "Disallow: /api/"
  end

  test "error page returns correct status code" do
    get "/nonexistent-page-xyz-123"
    assert_response :not_found
  end

  test "API health endpoint has X-Robots-Tag header" do
    get "/api/v1/health"
    assert_response :success
    assert_equal "noindex", response.headers["X-Robots-Tag"]
  end

  test "homepage renders successfully" do
    get "/"
    assert_response :success
  end

  test "libraries index renders successfully" do
    get "/libraries"
    assert_response :success
  end

  test "rankings renders successfully" do
    get "/rankings"
    assert_response :success
  end
end
