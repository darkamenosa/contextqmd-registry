# frozen_string_literal: true

require "test_helper"

class SeoTest < ActionDispatch::IntegrationTest
  # request.base_url in test env is http://www.example.com
  HOST = "http://www.example.com"

  test "sitemap.xml returns sitemap index with static child" do
    get "/sitemap.xml"
    assert_response :success
    assert_equal "application/xml; charset=utf-8", response.content_type
    assert_includes response.body, "<sitemapindex"
    assert_includes response.body, "#{HOST}/sitemap_static_1.xml"
  end

  test "sitemap.xml includes library child sitemaps with properly escaped ID ranges" do
    skip "No libraries in test DB" unless Library.not_cancelled.any?

    get "/sitemap.xml"
    # ERB escapes & to &amp; — exactly once
    assert_includes response.body, "sitemap_libraries_1.xml?from="
    assert_includes response.body, "&amp;to="
    assert_not_includes response.body, "&amp;amp;"
  end

  test "static sitemap includes marketing pages" do
    get "/sitemap_static_1.xml"
    assert_response :success
    assert_equal "application/xml; charset=utf-8", response.content_type
    assert_includes response.body, "<urlset"
    assert_includes response.body, "<loc>#{HOST}/</loc>"
    assert_includes response.body, "<loc>#{HOST}/libraries</loc>"
    assert_includes response.body, "<loc>#{HOST}/rankings</loc>"
    assert_includes response.body, "<loc>#{HOST}/about</loc>"
  end

  test "libraries sitemap returns data with valid from/to params" do
    lib = Library.not_cancelled.first
    skip "No libraries in test DB" unless lib

    get "/sitemap_libraries_1.xml", params: { from: lib.id, to: lib.id }
    assert_response :success
    assert_includes response.body, "<urlset"
    assert_includes response.body, "<loc>#{HOST}/libraries/#{lib.slug}</loc>"
  end

  test "libraries sitemap returns 404 without from/to params" do
    get "/sitemap_libraries_1.xml"
    assert_response :not_found
  end

  test "pages sitemap returns data with valid from/to params" do
    page = Page.joins(version: :library)
               .where("versions.version = libraries.default_version")
               .first
    skip "No default-version pages in test DB" unless page

    get "/sitemap_pages_1.xml", params: { from: page.id, to: page.id }
    assert_response :success
    assert_includes response.body, "<urlset"
    assert_includes response.body, page.page_uid
  end

  test "pages sitemap returns 404 without from/to params" do
    get "/sitemap_pages_1.xml"
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
