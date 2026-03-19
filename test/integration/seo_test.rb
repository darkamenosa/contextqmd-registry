# frozen_string_literal: true

require "test_helper"

class SeoTest < ActionDispatch::IntegrationTest
  test "sitemap.xml returns sitemap index with static sub-sitemap" do
    get "/sitemap.xml"
    assert_response :success
    assert_equal "application/xml; charset=utf-8", response.content_type
    assert_includes response.body, "<sitemapindex"
    assert_includes response.body, "https://contextqmd.com/sitemaps/static.xml"
  end

  test "sitemap.xml includes library sub-sitemaps when libraries exist" do
    skip "No libraries in test DB" unless Library.any?

    get "/sitemap.xml"
    assert_includes response.body, "https://contextqmd.com/sitemaps/libraries/1.xml"
  end

  test "static sitemap includes marketing pages" do
    get "/sitemaps/static.xml"
    assert_response :success
    assert_equal "application/xml; charset=utf-8", response.content_type
    assert_includes response.body, "<urlset"
    assert_includes response.body, "<loc>https://contextqmd.com/</loc>"
    assert_includes response.body, "<loc>https://contextqmd.com/libraries</loc>"
    assert_includes response.body, "<loc>https://contextqmd.com/rankings</loc>"
    assert_includes response.body, "<loc>https://contextqmd.com/about</loc>"
  end

  test "libraries sitemap includes library URLs" do
    lib = Library.first
    skip "No libraries in test DB" unless lib

    get "/sitemaps/libraries/1.xml"
    assert_response :success
    assert_includes response.body, "<urlset"
    assert_includes response.body, "<loc>https://contextqmd.com/libraries/#{lib.slug}</loc>"
  end

  test "pages sitemap includes doc page URLs" do
    page = Page.joins(version: :library)
               .where("versions.version = libraries.default_version")
               .first
    skip "No default-version pages in test DB" unless page

    get "/sitemaps/pages/1.xml"
    assert_response :success
    assert_includes response.body, "<urlset"
    assert_includes response.body, page.page_uid
  end

  test "sitemap sub-sitemaps return 404 for out-of-range page" do
    get "/sitemaps/libraries/9999.xml"
    assert_response :not_found
  end

  test "robots.txt is served with sitemap directive" do
    get "/robots.txt"
    assert_response :success
    assert_includes response.body, "Sitemap: https://contextqmd.com/sitemap.xml"
    assert_includes response.body, "Disallow: /admin/"
    assert_includes response.body, "Disallow: /api/"
    assert_includes response.body, "Disallow: /crawl"
    assert_includes response.body, "Disallow: /errors/"
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
