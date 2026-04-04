# frozen_string_literal: true

require "test_helper"

class Analytics::RollupRefreshStateTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    Analytics::RollupRefreshState.delete_all
    Analytics::Site.delete_all
  end

  test "cleanup_processed_before removes only completed stale rows" do
    travel_to Time.zone.parse("2026-04-04 10:00:00") do
      site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")

      stale_processed = Analytics::RollupRefreshState.create!(
        analytics_site: site,
        bucket_start: Time.zone.parse("2026-04-01 09:00:00"),
        rollup_key: "site-page-hourly-rollup",
        request_version: 2,
        processed_version: 2,
        processed_at: 8.days.ago,
        enqueued_at: nil
      )
      Analytics::RollupRefreshState.create!(
        analytics_site: site,
        bucket_start: Time.zone.parse("2026-04-04 09:00:00"),
        rollup_key: "site-source-hourly-rollup",
        request_version: 2,
        processed_version: 2,
        processed_at: 1.day.ago,
        enqueued_at: nil
      )
      Analytics::RollupRefreshState.create!(
        analytics_site: site,
        bucket_start: Time.zone.parse("2026-04-04 08:00:00"),
        rollup_key: "site-location-hourly-rollup",
        request_version: 3,
        processed_version: 2,
        processed_at: 8.days.ago,
        enqueued_at: Time.current
      )

      assert_difference -> { Analytics::RollupRefreshState.count }, -1 do
        Analytics::RollupRefreshState.cleanup_processed_before!(7.days.ago)
      end

      assert_not Analytics::RollupRefreshState.exists?(stale_processed.id)
      assert_equal 2, Analytics::RollupRefreshState.count
    end
  end
end
