# frozen_string_literal: true

require "test_helper"

class Admin::AnalyticsGoogleSearchConsoleTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  INERTIA_HEADERS = {
    "X-Inertia" => "true",
    "X-Inertia-Version" => ViteRuby.digest,
    "X-Requested-With" => "XMLHttpRequest",
    "ACCEPT" => "text/html, application/xhtml+xml"
  }.freeze

  setup do
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs

    Analytics::GoogleSearchConsole::QueryRow.delete_all
    Analytics::GoogleSearchConsole::Sync.delete_all
    Analytics::Setting.delete_all
    Analytics::GoogleSearchConsoleConnection.delete_all
    Analytics::SiteBoundary.delete_all
    Analytics::Site.delete_all
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    ActiveJob::Base.queue_adapter = @original_queue_adapter
  end

  test "settings shell includes disconnected google search console state" do
    staff_identity, = create_tenant(
      email: "staff-analytics-gsc-shell-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics GSC Shell"
    )
    staff_identity.update!(staff: true)

    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")

    sign_in(staff_identity)

    with_google_search_console_configured do
      get "/admin/settings/analytics", headers: INERTIA_HEADERS
    end

    assert_response :success

    payload = JSON.parse(response.body).fetch("props")
    gsc = payload.fetch("settings").fetch("googleSearchConsole")

    assert_equal false, gsc.fetch("connected")
    assert_equal false, gsc.fetch("configured")
    assert_equal true, gsc.fetch("available")
    assert_equal "/admin/settings/analytics/google_search_console/callback", gsc.fetch("callbackPath")
    assert_equal "http://www.example.com/admin/settings/analytics/google_search_console/callback", gsc.fetch("callbackUrl")
    assert_equal "/admin/settings/analytics", payload.fetch("paths").fetch("settings")
    assert_equal "/admin/analytics/sites/#{site.public_id}/google_search_console/connect", payload.fetch("paths").fetch("googleSearchConsoleConnect")
    assert_equal "/admin/analytics/sites/#{site.public_id}/google_search_console/sync", payload.fetch("paths").fetch("googleSearchConsoleSync")
  ensure
    Current.reset
  end

  test "legacy analytics settings route redirects to settings analytics page" do
    staff_identity, = create_tenant(
      email: "staff-analytics-gsc-legacy-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics GSC Legacy"
    )
    staff_identity.update!(staff: true)

    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")

    sign_in(staff_identity)

    get "/admin/analytics/sites/#{site.public_id}/settings"

    assert_redirected_to "/admin/settings/analytics"
  ensure
    Current.reset
  end

  test "connect callback creates a site-scoped google search console connection" do
    staff_identity, = create_tenant(
      email: "staff-analytics-gsc-connect-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics GSC Connect"
    )
    staff_identity.update!(staff: true)

    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    fake_client = FakeGoogleSearchConsoleClient.new(
      properties: [
        {
          identifier: "https://docs.example.test/",
          type: "url_prefix",
          permission_level: "siteFullUser",
          label: "docs.example.test"
        }
      ]
    )

    sign_in(staff_identity)

    with_google_search_console_configured do
      with_google_search_console_client(fake_client) do
        assert_enqueued_jobs 1, only: Analytics::GoogleSearchConsoleSyncJob do
          post "/admin/analytics/sites/#{site.public_id}/google_search_console/connect"

          assert_response :redirect
          assert_match "https://accounts.google.com/o/oauth2/v2/auth", response.location
          assert fake_client.last_state.present?

          get "/admin/settings/analytics/google_search_console/callback",
            params: { code: "google-auth-code", state: fake_client.last_state }
        end
      end
    end

    assert_redirected_to "/admin/settings/analytics?tab=integrations"

    connection = Analytics::GoogleSearchConsoleConnection.current_for(site)
    assert_not_nil connection
    assert_equal site.id, connection.analytics_site_id
    assert_equal "owner@example.com", connection.google_email
    assert_equal "google-user-123", connection.google_uid
    assert_equal "https://docs.example.test/", connection.property_identifier
    assert_equal "url_prefix", connection.property_type
  ensure
    Current.reset
  end

  test "property selection and disconnect update the active connection" do
    staff_identity, = create_tenant(
      email: "staff-analytics-gsc-update-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics GSC Update"
    )
    staff_identity.update!(staff: true)

    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    connection = Analytics::GoogleSearchConsoleConnection.rotate_for_site!(
      site: site,
      attributes: {
        google_uid: "google-user-456",
        google_email: "owner@example.com",
        access_token: "access-token",
        refresh_token: "refresh-token",
        expires_at: 1.hour.from_now,
        scopes: Analytics::GoogleSearchConsole::Client::SCOPES,
        metadata: {}
      }
    )
    fake_client = FakeGoogleSearchConsoleClient.new(
      properties: [
        {
          identifier: "sc-domain:example.com",
          type: "domain",
          permission_level: "siteOwner",
          label: "example.com"
        },
        {
          identifier: "https://docs.example.test/",
          type: "url_prefix",
          permission_level: "siteFullUser",
          label: "docs.example.test"
        }
      ]
    )

    sign_in(staff_identity)

    with_google_search_console_configured do
      with_google_search_console_client(fake_client) do
        assert_enqueued_jobs 1, only: Analytics::GoogleSearchConsoleSyncJob do
          patch "/admin/analytics/sites/#{site.public_id}/google_search_console",
            params: {
              google_search_console: {
                property_identifier: "sc-domain:example.com"
              }
            }
        end
      end
    end

    assert_redirected_to "/admin/settings/analytics?tab=integrations"

    connection.reload
    assert_equal "sc-domain:example.com", connection.property_identifier
    assert_equal "domain", connection.property_type
    assert_equal "siteOwner", connection.permission_level

    delete "/admin/analytics/sites/#{site.public_id}/google_search_console"

    assert_redirected_to "/admin/settings/analytics?tab=integrations"

    connection.reload
    assert_equal false, connection.active
    assert_equal Analytics::GoogleSearchConsoleConnection::STATUS_DISCONNECTED, connection.status
    assert_nil Analytics::GoogleSearchConsoleConnection.current_for(site)
  ensure
    Current.reset
  end

  test "manual sync queues a retry and settings payload exposes stale sync state" do
    staff_identity, = create_tenant(
      email: "staff-analytics-gsc-sync-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics GSC Sync"
    )
    staff_identity.update!(staff: true)

    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    connection = Analytics::GoogleSearchConsoleConnection.rotate_for_site!(
      site: site,
      attributes: {
        google_uid: "google-user-456",
        google_email: "owner@example.com",
        access_token: "access-token",
        refresh_token: "refresh-token",
        expires_at: 1.hour.from_now,
        scopes: Analytics::GoogleSearchConsole::Client::SCOPES,
        metadata: {},
        property_identifier: "sc-domain:docs.example.test",
        property_type: "domain",
        permission_level: "siteOwner",
        last_verified_at: Time.current
      }
    )
    connection.syncs.create!(
      property_identifier: connection.property_identifier,
      search_type: "web",
      from_date: 90.days.ago.to_date,
      to_date: 20.days.ago.to_date,
      started_at: 1.hour.ago,
      finished_at: 55.minutes.ago,
      status: Analytics::GoogleSearchConsole::Sync::STATUS_FAILED,
      error_message: "quota exceeded"
    )
    fake_client = FakeGoogleSearchConsoleClient.new(properties: [])

    sign_in(staff_identity)

    with_google_search_console_configured do
      with_google_search_console_client(fake_client) do
        get "/admin/settings/analytics", headers: INERTIA_HEADERS
      end
    end

    assert_response :success

    payload = JSON.parse(response.body).fetch("props")
    gsc = payload.fetch("settings").fetch("googleSearchConsole")
    assert_equal true, gsc.fetch("syncStale")
    assert_equal "quota exceeded", gsc.fetch("syncError")

    with_google_search_console_configured do
      assert_enqueued_jobs 1, only: Analytics::GoogleSearchConsoleSyncJob do
        post "/admin/analytics/sites/#{site.public_id}/google_search_console/sync"
      end
    end

    assert_redirected_to "/admin/settings/analytics?tab=integrations"
  ensure
    Current.reset
  end

  class FakeGoogleSearchConsoleClient
    attr_reader :last_state

    def initialize(properties:)
      @properties = properties
      @last_state = nil
    end

    def authorization_url(state:)
      @last_state = state
      "https://accounts.google.com/o/oauth2/v2/auth?state=#{CGI.escape(state)}"
    end

    def exchange_code!(code)
      raise "unexpected code" unless code == "google-auth-code"

      {
        "access_token" => "google-access-token",
        "refresh_token" => "google-refresh-token",
        "expires_in" => 3600,
        "scope" => Analytics::GoogleSearchConsole::Client::SCOPES.join(" ")
      }
    end

    def fetch_user_profile(_access_token)
      {
        "sub" => "google-user-123",
        "email" => "owner@example.com"
      }
    end

    def list_verified_properties(_access_token)
      @properties
    end

    def refresh_access_token!(_refresh_token)
      {
        "access_token" => "google-access-token-refreshed",
        "expires_in" => 3600,
        "scope" => Analytics::GoogleSearchConsole::Client::SCOPES.join(" ")
      }
    end
  end

  private
    def with_google_search_console_configured
      original_configured = Analytics::GoogleSearchConsole::Configuration.method(:configured?)
      Analytics::GoogleSearchConsole::Configuration.define_singleton_method(:configured?) { true }
      yield
    ensure
      Analytics::GoogleSearchConsole::Configuration.define_singleton_method(:configured?, original_configured)
    end

    def with_google_search_console_client(fake_client)
      original_new = Analytics::GoogleSearchConsole::Client.method(:new)
      Analytics::GoogleSearchConsole::Client.define_singleton_method(:new) do |*|
        fake_client
      end
      yield
    ensure
      Analytics::GoogleSearchConsole::Client.define_singleton_method(:new, original_new)
    end
end
