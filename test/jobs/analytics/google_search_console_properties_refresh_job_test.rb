# frozen_string_literal: true

require "test_helper"

class Analytics::GoogleSearchConsolePropertiesRefreshJobTest < ActiveSupport::TestCase
  setup do
    Analytics::GoogleSearchConsoleConnection.delete_all
    Analytics::Site.delete_all
  end

  test "refreshes cached verified properties for an active connection" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    connection = create_connection_for(site, expires_at: 1.hour.ago)
    fake_client = FakeGoogleSearchConsoleClient.new(
      properties: [
        {
          identifier: "sc-domain:docs.example.test",
          type: "domain",
          permission_level: "siteOwner",
          label: "docs.example.test"
        }
      ]
    )

    with_google_search_console_client(fake_client) do
      Analytics::GoogleSearchConsolePropertiesRefreshJob.perform_now(connection.id)
    end

    connection.reload
    assert_equal Analytics::GoogleSearchConsoleConnection::STATUS_ACTIVE, connection.status
    assert_equal "docs.example.test", connection.cached_properties.first&.fetch(:label)
    assert_nil connection.properties_refresh_error
    assert_not_nil connection.properties_refreshed_at
  end

  test "marks the connection as revoked when the refresh token is invalid" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    connection = create_connection_for(site, expires_at: 1.hour.ago)
    fake_client = FakeGoogleSearchConsoleClient.new(
      properties: [],
      refresh_error: Analytics::GoogleSearchConsole::Client::Error.new(
        "Token has been expired or revoked.",
        reason: :reauth_required
      )
    )

    assert_raises(Analytics::GoogleSearchConsole::Client::Error) do
      with_google_search_console_client(fake_client) do
        Analytics::GoogleSearchConsolePropertiesRefreshJob.perform_now(connection.id)
      end
    end

    connection.reload
    assert_equal Analytics::GoogleSearchConsoleConnection::STATUS_REVOKED, connection.status
    assert_equal "Token has been expired or revoked.", connection.connection_error_message
  end

  private
    def create_connection_for(site, expires_at:)
      Analytics::GoogleSearchConsoleConnection.rotate_for_site!(
        site: site,
        attributes: {
          google_uid: "google-user-#{SecureRandom.hex(4)}",
          google_email: "#{site.name.downcase}@example.com",
          access_token: "access-token",
          refresh_token: "refresh-token",
          expires_at: expires_at,
          scopes: Analytics::GoogleSearchConsole::Client::SCOPES,
          metadata: {},
          property_identifier: "sc-domain:#{site.canonical_hostname}",
          property_type: "domain",
          permission_level: "siteOwner",
          last_verified_at: Time.current
        }
      )
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

    class FakeGoogleSearchConsoleClient
      def initialize(properties:, refresh_error: nil)
        @properties = properties
        @refresh_error = refresh_error
      end

      def list_verified_properties(_access_token)
        @properties
      end

      def refresh_access_token!(_refresh_token)
        raise @refresh_error if @refresh_error.present?

        {
          "access_token" => "refreshed-access-token",
          "expires_in" => 3600,
          "scope" => Analytics::GoogleSearchConsole::Client::SCOPES.join(" ")
        }
      end
    end
end
