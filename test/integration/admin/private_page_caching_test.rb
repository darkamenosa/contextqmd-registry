# frozen_string_literal: true

require "test_helper"

class Admin::PrivatePageCachingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  INERTIA_HEADERS = {
    "X-Inertia" => "true",
    "X-Inertia-Version" => ViteRuby.digest,
    "X-Requested-With" => "XMLHttpRequest"
  }.freeze

  test "dashboard uses private conditional caching and keeps html/inertia variants separate" do
    identity, = create_tenant(
      email: "admin-dashboard-cache-#{SecureRandom.hex(4)}@example.com",
      name: "Admin Dashboard Cache"
    )
    identity.update!(staff: true)

    sign_in(identity)

    get admin_dashboard_path

    assert_response :success
    assert_includes response.headers["Cache-Control"], "private"
    assert_includes response.headers["Vary"], "X-Inertia"

    html_etag = response.headers["ETag"]
    assert html_etag.present?

    get admin_dashboard_path, headers: { "If-None-Match" => html_etag }

    assert_response :not_modified

    get admin_dashboard_path, headers: INERTIA_HEADERS.merge("If-None-Match" => html_etag)

    assert_response :success
    assert_equal "true", response.headers["X-Inertia"]
    assert_equal "application/json; charset=utf-8", response.content_type

    inertia_etag = response.headers["ETag"]
    assert inertia_etag.present?
    refute_equal html_etag, inertia_etag

    get admin_dashboard_path, headers: INERTIA_HEADERS.merge("If-None-Match" => inertia_etag)

    assert_response :not_modified
  ensure
    Current.reset
  end

  test "dashboard invalidates when library counters change" do
    identity, = create_tenant(
      email: "admin-dashboard-counter-cache-#{SecureRandom.hex(4)}@example.com",
      name: "Admin Dashboard Counter Cache"
    )
    identity.update!(staff: true)

    sign_in(identity)

    get admin_dashboard_path, headers: INERTIA_HEADERS

    assert_response :success
    stale_etag = response.headers["ETag"]
    assert stale_etag.present?

    stats = response.parsed_body.dig("props", "stats")

    hex = SecureRandom.hex(4)
    library = Library.create!(
      account: Account.system,
      namespace: "admin-counter-cache-#{hex}",
      name: "docs-#{hex}",
      slug: "admin-counter-cache-#{hex}",
      display_name: "Admin Counter Cache",
      source_type: "github"
    )
    library.update_columns(versions_count: 7, total_pages_count: 42)

    get admin_dashboard_path, headers: INERTIA_HEADERS.merge("If-None-Match" => stale_etag)

    assert_response :success
    updated_stats = response.parsed_body.dig("props", "stats")
    assert_equal stats.fetch("libraryCount") + 1, updated_stats.fetch("libraryCount")
    assert_equal stats.fetch("versionCount") + 7, updated_stats.fetch("versionCount")
    assert_equal stats.fetch("pageCount") + 42, updated_stats.fetch("pageCount")
  ensure
    Current.reset
  end
end
