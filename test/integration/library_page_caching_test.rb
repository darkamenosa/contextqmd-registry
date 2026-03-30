# frozen_string_literal: true

require "test_helper"

class LibraryPageCachingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    hex = SecureRandom.hex(4)
    account = Account.system

    @library = Library.create!(
      account: account,
      namespace: "cache-#{hex}",
      name: "library-#{hex}",
      slug: "library-#{hex}",
      display_name: "Library #{hex}",
      default_version: "1.0.0"
    )

    @version = @library.versions.create!(
      version: "1.0.0",
      channel: "stable",
      generated_at: Time.current,
      pages_count: 1
    )

    @page = @version.pages.create!(
      page_uid: "page-#{hex}",
      path: "docs/overview.md",
      title: "Overview",
      description: "Overview content",
      url: "https://docs.example.com/overview",
      checksum: "sha256:page-#{hex}",
      bytes: 1024,
      headings: [ "Overview" ]
    )

    @library.update_columns(total_pages_count: 1, latest_version_at: @version.created_at)
  end

  test "library page detail responds with public cache headers and supports conditional get" do
    get "/libraries/#{@library.slug}/versions/#{@version.version}/pages/#{@page.page_uid}"

    assert_response :success
    assert_includes response.headers["Cache-Control"], "public"
    assert_includes response.headers["Cache-Control"], "max-age=3600"
    assert_equal "public, max-age=3600, stale-while-revalidate=60", response.headers["Cloudflare-CDN-Cache-Control"]

    etag = response.headers["ETag"]
    assert etag.present?

    get(
      "/libraries/#{@library.slug}/versions/#{@version.version}/pages/#{@page.page_uid}",
      headers: { "If-None-Match" => etag }
    )

    assert_response :not_modified
  end

  test "inertia navigation request still returns an inertia response instead of conditional html caching" do
    get(
      "/libraries/#{@library.slug}/versions/#{@version.version}/pages/#{@page.page_uid}",
      headers: {
        "X-Inertia" => "true",
        "X-Inertia-Version" => ViteRuby.digest
      }
    )

    assert_response :success
    assert_equal "true", response.headers["X-Inertia"]
    assert_equal "application/json; charset=utf-8", response.content_type
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_nil response.headers["Cloudflare-CDN-Cache-Control"]
  end

  test "authenticated html request does not emit public cache headers" do
    identity = Identity.create!(
      email: "cache-test-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    User.create!(
      account: @library.account,
      identity: identity,
      name: "Cache Test User",
      role: "member"
    )

    sign_in(identity)

    get "/libraries/#{@library.slug}/versions/#{@version.version}/pages/#{@page.page_uid}"

    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_nil response.headers["Cloudflare-CDN-Cache-Control"]
  end
end
