# frozen_string_literal: true

require "test_helper"

class PublicPageCachingTest < ActionDispatch::IntegrationTest
  INERTIA_HEADERS = {
    "X-Inertia" => "true",
    "X-Inertia-Version" => ViteRuby.digest,
    "X-Requested-With" => "XMLHttpRequest"
  }.freeze

  test "about page uses conditional caching and keeps html and inertia variants separate" do
    get about_path

    assert_response :success
    assert_includes response.headers["Cache-Control"], "private"
    assert_includes response.headers["Vary"], "X-Inertia"

    html_etag = response.headers["ETag"]
    assert html_etag.present?

    get about_path, headers: { "If-None-Match" => html_etag }

    assert_response :not_modified

    get about_path, headers: INERTIA_HEADERS.merge("If-None-Match" => html_etag)

    assert_response :success
    assert_equal "true", response.headers["X-Inertia"]

    inertia_etag = response.headers["ETag"]
    assert inertia_etag.present?
    refute_equal html_etag, inertia_etag

    get about_path, headers: INERTIA_HEADERS.merge("If-None-Match" => inertia_etag)

    assert_response :not_modified
  end

  test "authenticated public page invalidates when shared identity account state changes" do
    identity, account, = create_tenant(
      email: "public-auth-cache-#{SecureRandom.hex(4)}@example.com",
      name: "Public Auth Cache"
    )

    sign_in_with_password(identity)
    consume_post_login_public_flash

    get about_path

    assert_response :success
    stale_etag = response.headers["ETag"]
    assert stale_etag.present?

    account.update!(name: "Renamed Public Account")

    get about_path, headers: { "If-None-Match" => stale_etag }

    assert_response :success
    refute_equal stale_etag, response.headers["ETag"]
  ensure
    Current.reset
  end

  test "libraries index uses conditional caching and keeps html and inertia variants separate" do
    hex = SecureRandom.hex(4)
    Library.create!(
      account: Account.system,
      namespace: "public-cache-#{hex}",
      name: "docs-#{hex}",
      slug: "public-cache-#{hex}",
      display_name: "Public Cache Docs",
      source_type: "github"
    )

    get libraries_path

    assert_response :success
    assert_includes response.headers["Cache-Control"], "private"
    assert_includes response.headers["Vary"], "X-Inertia"

    html_etag = response.headers["ETag"]
    assert html_etag.present?

    get libraries_path, headers: { "If-None-Match" => html_etag }

    assert_response :not_modified

    get libraries_path, headers: INERTIA_HEADERS.merge("If-None-Match" => html_etag)

    assert_response :success
    assert_equal "true", response.headers["X-Inertia"]

    inertia_etag = response.headers["ETag"]
    assert inertia_etag.present?
    refute_equal html_etag, inertia_etag

    get libraries_path, headers: INERTIA_HEADERS.merge("If-None-Match" => inertia_etag)

    assert_response :not_modified
  ensure
    Current.reset
  end

  test "libraries index invalidates when displayed library counters change" do
    hex = SecureRandom.hex(4)
    library = Library.create!(
      account: Account.system,
      namespace: "public-counter-cache-#{hex}",
      name: "docs-#{hex}",
      slug: "public-counter-cache-#{hex}",
      display_name: "Public Counter Cache Docs",
      source_type: "github"
    )
    version = library.versions.create!(version: "1.0.0", channel: "stable")

    get libraries_path, headers: INERTIA_HEADERS

    assert_response :success
    stale_etag = response.headers["ETag"]
    assert stale_etag.present?

    version.pages.create!(
      page_uid: "intro",
      path: "intro.md",
      title: "Intro",
      description: "Counter cache page"
    )
    version.reconcile_pages_count

    get libraries_path, headers: INERTIA_HEADERS.merge("If-None-Match" => stale_etag)

    assert_response :success
    refute_equal stale_etag, response.headers["ETag"]
  ensure
    Current.reset
  end

  test "homepage supports html revalidation" do
    get root_path

    assert_response :success

    html_etag = response.headers["ETag"]
    assert html_etag.present?

    get root_path, headers: { "If-None-Match" => html_etag }

    assert_response :not_modified
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

    def consume_post_login_public_flash
      get about_path
      assert_response :success
    end
end
