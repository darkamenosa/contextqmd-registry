# frozen_string_literal: true

require "test_helper"

class App::PrivatePageCachingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  INERTIA_HEADERS = {
    "X-Inertia" => "true",
    "X-Inertia-Version" => ViteRuby.digest,
    "X-Requested-With" => "XMLHttpRequest"
  }.freeze

  test "dashboard uses private conditional caching and keeps html/inertia variants separate" do
    identity, account, = create_tenant(
      email: "dashboard-cache-#{SecureRandom.hex(4)}@example.com",
      name: "Dashboard Cache"
    )

    sign_in(identity)

    get app_dashboard_path(account_id: account.external_account_id)

    assert_response :success
    assert_includes response.headers["Cache-Control"], "private"
    assert_includes response.headers["Vary"], "X-Inertia"

    html_etag = response.headers["ETag"]
    assert html_etag.present?

    get(
      app_dashboard_path(account_id: account.external_account_id),
      headers: { "If-None-Match" => html_etag }
    )

    assert_response :not_modified

    get(
      app_dashboard_path(account_id: account.external_account_id),
      headers: INERTIA_HEADERS.merge("If-None-Match" => html_etag)
    )

    assert_response :success
    assert_equal "true", response.headers["X-Inertia"]
    assert_equal "application/json; charset=utf-8", response.content_type

    inertia_etag = response.headers["ETag"]
    assert inertia_etag.present?
    refute_equal html_etag, inertia_etag

    get(
      app_dashboard_path(account_id: account.external_account_id),
      headers: INERTIA_HEADERS.merge("If-None-Match" => inertia_etag)
    )

    assert_response :not_modified
  ensure
    Current.reset
  end

  test "settings disables conditional caching when flash is present, then returns to private etag caching" do
    identity, account, user = create_tenant(
      email: "settings-cache-#{SecureRandom.hex(4)}@example.com",
      name: "Settings Cache"
    )

    sign_in(identity)

    patch app_settings_path(account_id: account.external_account_id), params: {
      settings: { name: "Updated Cache Name" }
    }, headers: INERTIA_HEADERS

    assert_redirected_to app_settings_path(account_id: account.external_account_id)

    get app_settings_path(account_id: account.external_account_id), headers: INERTIA_HEADERS

    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal "Updated Cache Name", response.parsed_body.dig("props", "name")

    flash_response_etag = response.headers["ETag"]
    assert flash_response_etag.present?

    user.reload
    assert_equal "Updated Cache Name", user.name

    get(
      app_settings_path(account_id: account.external_account_id),
      headers: INERTIA_HEADERS.merge("If-None-Match" => flash_response_etag)
    )

    assert_response :success
    assert_includes response.headers["Cache-Control"], "private"

    settings_etag = response.headers["ETag"]
    assert settings_etag.present?

    get(
      app_settings_path(account_id: account.external_account_id),
      headers: INERTIA_HEADERS.merge("If-None-Match" => settings_etag)
    )

    assert_response :not_modified
  ensure
    Current.reset
  end
end
