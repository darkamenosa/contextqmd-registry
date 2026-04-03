# frozen_string_literal: true

require "test_helper"

class Analytics::SiteEventHourlyRollupTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  setup do
    Analytics::SiteEventHourlyRollup.delete_all if Analytics::SiteEventHourlyRollup.available?
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
    Analytics::SiteBoundary.delete_all
    Analytics::Site.delete_all
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "usable_for stays false until every full bucket in range is refreshed" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
      visit = create_visit(site:, started_at: Time.zone.parse("2026-03-25 09:00:00"))

      create_pageview(site:, visit:, time: Time.zone.parse("2026-03-25 09:10:00"), page: "/docs")
      create_pageview(site:, visit:, time: Time.zone.parse("2026-03-25 10:10:00"), page: "/pricing")

      range = Time.zone.parse("2026-03-25 09:00:00")..Time.zone.parse("2026-03-25 10:59:59")
      Analytics::SiteEventHourlyRollup.refresh_bucket!(site:, bucket_start: Time.zone.parse("2026-03-25 09:00:00"))

      assert_not Analytics::SiteEventHourlyRollup.usable_for?(range:, site:)

      Analytics::SiteEventHourlyRollup.refresh_bucket!(site:, bucket_start: Time.zone.parse("2026-03-25 10:00:00"))

      assert Analytics::SiteEventHourlyRollup.usable_for?(range:, site:)
    end
  end

  test "sum_for and series_for trim partial edge hours exactly" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
      visit = create_visit(site:, started_at: Time.zone.parse("2026-03-25 09:00:00"))

      create_pageview(site:, visit:, time: Time.zone.parse("2026-03-25 09:10:00"), page: "/edge-early")
      create_pageview(site:, visit:, time: Time.zone.parse("2026-03-25 09:50:00"), page: "/edge-late")
      create_pageview(site:, visit:, time: Time.zone.parse("2026-03-25 10:10:00"), page: "/middle-a")
      create_pageview(site:, visit:, time: Time.zone.parse("2026-03-25 10:50:00"), page: "/middle-b")
      create_pageview(site:, visit:, time: Time.zone.parse("2026-03-25 11:10:00"), page: "/edge-end")

      Analytics::SiteEventHourlyRollup.refresh_range!(
        site: site,
        range: Time.zone.parse("2026-03-25 09:00:00")..Time.zone.parse("2026-03-25 11:59:59")
      )

      range = Time.zone.parse("2026-03-25 09:30:00")..Time.zone.parse("2026-03-25 11:30:00")

      assert_equal 4, Analytics::SiteEventHourlyRollup.sum_for(range:, site:, column: :pageviews_count)

      series = Analytics::SiteEventHourlyRollup.series_for(range:, interval: "hour", site:, column: :pageviews_count)

      assert_equal 1, series.fetch(Time.zone.parse("2026-03-25 09:00:00").utc)
      assert_equal 2, series.fetch(Time.zone.parse("2026-03-25 10:00:00").utc)
      assert_equal 1, series.fetch(Time.zone.parse("2026-03-25 11:00:00").utc)
    end
  end

  test "refresh_later enqueues again after a completed refresh inside the coalesce window" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
      visit = create_visit(site:, started_at: Time.zone.parse("2026-03-25 09:00:00"))
      bucket_start = Time.zone.parse("2026-03-25 09:00:00")

      create_pageview(site:, visit:, time: Time.zone.parse("2026-03-25 09:10:00"), page: "/docs")

      assert_enqueued_jobs 1, only: Analytics::SiteEventHourlyRollupRefreshJob do
        Analytics::SiteEventHourlyRollup.refresh_later(site:, bucket_start:)
      end

      clear_enqueued_jobs
      Analytics::SiteEventHourlyRollupRefreshJob.perform_now(site.id, bucket_start)

      create_pageview(site:, visit:, time: Time.zone.parse("2026-03-25 09:20:00"), page: "/pricing")

      assert_enqueued_jobs 1, only: Analytics::SiteEventHourlyRollupRefreshJob do
        Analytics::SiteEventHourlyRollup.refresh_later(site:, bucket_start:)
      end

      Analytics::SiteEventHourlyRollupRefreshJob.perform_now(site.id, bucket_start)

      assert_equal 2, Analytics::SiteEventHourlyRollup.find_by!(analytics_site: site, bucket_start:).pageviews_count
    end
  end

  private
    def create_visit(site:, started_at:)
      Ahoy::Visit.create!(
        analytics_site: site,
        visit_token: SecureRandom.hex(16),
        visitor_token: SecureRandom.hex(16),
        started_at: started_at
      )
    end

    def create_pageview(site:, visit:, time:, page:)
      Ahoy::Event.create!(
        analytics_site: site,
        visit: visit,
        name: "pageview",
        time: time,
        properties: { page: page }
      )
    end
end
