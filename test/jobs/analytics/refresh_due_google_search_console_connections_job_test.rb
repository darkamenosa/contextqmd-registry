# frozen_string_literal: true

require "test_helper"

class Analytics::RefreshDueGoogleSearchConsoleConnectionsJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs

    Analytics::GoogleSearchConsole::QueryRow.delete_all
    Analytics::GoogleSearchConsole::Sync.delete_all
    Analytics::GoogleSearchConsoleConnection.delete_all
    Analytics::Site.delete_all
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    ActiveJob::Base.queue_adapter = @original_queue_adapter
  end

  test "enqueues sync jobs only for active configured connections with stale coverage" do
    now = Time.zone.parse("2026-03-29 12:00:00")
    from_date, to_date = Analytics::GoogleSearchConsole::Syncer.refresh_sync_window(now: now)

    stale_site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    stale_connection = create_connection_for(stale_site)

    fresh_site = Analytics::Site.create!(name: "Blog", canonical_hostname: "blog.example.test")
    fresh_connection = create_connection_for(fresh_site)
    fresh_connection.syncs.create!(
      property_identifier: fresh_connection.property_identifier,
      search_type: "web",
      from_date: from_date,
      to_date: to_date,
      started_at: now - 10.minutes,
      finished_at: now - 5.minutes,
      status: Analytics::GoogleSearchConsole::Sync::STATUS_SUCCEEDED
    )

    running_site = Analytics::Site.create!(name: "App", canonical_hostname: "app.example.test")
    running_connection = create_connection_for(running_site)
    running_connection.syncs.create!(
      property_identifier: running_connection.property_identifier,
      search_type: "web",
      from_date: from_date,
      to_date: to_date,
      started_at: now - 5.minutes,
      status: Analytics::GoogleSearchConsole::Sync::STATUS_RUNNING
    )

    disconnected_site = Analytics::Site.create!(name: "Shop", canonical_hostname: "shop.example.test")
    disconnected_connection = create_connection_for(disconnected_site)
    disconnected_connection.disconnect!

    assert_enqueued_jobs 1, only: Analytics::GoogleSearchConsoleSyncJob do
      Analytics::RefreshDueGoogleSearchConsoleConnectionsJob.perform_now(now)
    end

    enqueued = enqueued_jobs.find { |job| job[:job] == Analytics::GoogleSearchConsoleSyncJob }
    assert_not_nil enqueued
    assert_equal stale_connection.id, enqueued[:args][0]
  end

  private
    def create_connection_for(site)
      Analytics::GoogleSearchConsoleConnection.rotate_for_site!(
        site: site,
        attributes: {
          google_uid: "google-user-#{SecureRandom.hex(4)}",
          google_email: "#{site.name.downcase}@example.com",
          access_token: "access-token",
          refresh_token: "refresh-token",
          expires_at: 1.hour.from_now,
          scopes: Analytics::GoogleSearchConsole::Client::SCOPES,
          metadata: {},
          property_identifier: "sc-domain:#{site.canonical_hostname}",
          property_type: "domain",
          permission_level: "siteOwner",
          last_verified_at: Time.current
        }
      )
    end
end
