# frozen_string_literal: true

require "test_helper"

class App::PrivatePageCachingTest < ActionDispatch::IntegrationTest
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

    sign_in_with_password(identity)
    consume_post_login_dashboard_flash(account)

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

  test "dashboard html revalidation does not rewrite cookies on 304" do
    identity, account, = create_tenant(
      email: "dashboard-html-304-#{SecureRandom.hex(4)}@example.com",
      name: "Dashboard HTML 304"
    )

    sign_in_with_password(identity)
    consume_post_login_dashboard_flash(account)

    get app_dashboard_path(account_id: account.external_account_id)

    assert_response :success
    etag = response.headers["ETag"]
    assert etag.present?

    get(
      app_dashboard_path(account_id: account.external_account_id),
      headers: { "If-None-Match" => etag }
    )

    assert_response :not_modified
    assert_nil response.headers["Set-Cookie"]
  ensure
    Current.reset
  end

  test "dashboard stops rewriting cookies after the first authenticated request" do
    identity, account, = create_tenant(
      email: "dashboard-cookie-stability-#{SecureRandom.hex(4)}@example.com",
      name: "Dashboard Cookie Stability"
    )

    sign_in_with_password(identity)
    consume_post_login_dashboard_flash(account)

    get app_dashboard_path(account_id: account.external_account_id)

    assert_response :success

    get app_dashboard_path(account_id: account.external_account_id)

    assert_response :success
    assert_nil response.headers["Set-Cookie"]
  ensure
    Current.reset
  end

  test "dashboard invalidates when library counters change" do
    identity, account, user = create_tenant(
      email: "dashboard-counter-cache-#{SecureRandom.hex(4)}@example.com",
      name: "Dashboard Counter Cache"
    )

    library = Library.create!(
      account: Account.system,
      namespace: "counter-cache-#{SecureRandom.hex(4)}",
      name: "docs",
      slug: "counter-cache-docs-#{SecureRandom.hex(4)}",
      display_name: "Counter Cache Docs"
    )
    version = library.versions.create!(version: "1.0.0", channel: "stable")
    CrawlRequest.create!(
      creator: user,
      library: library,
      url: "https://example.com/counter-cache",
      source_type: "website",
      status: "completed"
    )

    sign_in_with_password(identity)
    consume_post_login_dashboard_flash(account)

    get app_dashboard_path(account_id: account.external_account_id), headers: INERTIA_HEADERS

    assert_response :success
    assert_equal 0, response.parsed_body.dig("props", "stats", "pageCount")

    stale_etag = response.headers["ETag"]
    assert stale_etag.present?

    version.pages.create!(
      page_uid: "intro",
      path: "intro.md",
      title: "Intro",
      description: "Counter cache page"
    )
    version.reconcile_pages_count

    get(
      app_dashboard_path(account_id: account.external_account_id),
      headers: INERTIA_HEADERS.merge("If-None-Match" => stale_etag)
    )

    assert_response :success
    assert_equal 1, response.parsed_body.dig("props", "stats", "pageCount")
  ensure
    Current.reset
  end

  test "dashboard stores payload in rails cache under the dashboard state key" do
    identity, account, user = create_tenant(
      email: "dashboard-payload-cache-#{SecureRandom.hex(4)}@example.com",
      name: "Dashboard Payload Cache"
    )

    cache_store = ActiveSupport::Cache.lookup_store(:memory_store)

    sign_in_with_password(identity)
    consume_post_login_dashboard_flash(account)

    with_stubbed_singleton_method(Rails, :cache, cache_store) do
      get app_dashboard_path(account_id: account.external_account_id), headers: INERTIA_HEADERS

      assert_response :success
      assert_operator cache_store.instance_variable_get(:@data).size, :>, 0
    end
  ensure
    Current.reset
  end

  test "settings disables conditional caching when flash is present, then returns to private etag caching" do
    identity, account, user = create_tenant(
      email: "settings-cache-#{SecureRandom.hex(4)}@example.com",
      name: "Settings Cache"
    )

    sign_in_with_password(identity)
    consume_post_login_dashboard_flash(account)

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

  private

    def sign_in_with_password(identity, password: "password123")
      post identity_session_path, params: {
        identity: {
          email: identity.email,
          password: password
        }
      }

      assert_response :redirect
    end

    def consume_post_login_dashboard_flash(account)
      get app_dashboard_path(account_id: account.external_account_id)
      assert_response :success
    end
end
