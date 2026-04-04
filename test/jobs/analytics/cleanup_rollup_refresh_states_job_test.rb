# frozen_string_literal: true

require "test_helper"

class Analytics::CleanupRollupRefreshStatesJobTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    Analytics::RollupRefreshState.delete_all
    Analytics::Site.delete_all
  end

  test "removes completed stale rollup refresh states" do
    travel_to Time.zone.parse("2026-04-04 10:00:00") do
      site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")

      Analytics::RollupRefreshState.create!(
        analytics_site: site,
        bucket_start: Time.zone.parse("2026-04-01 09:00:00"),
        rollup_key: "site-page-hourly-rollup",
        request_version: 1,
        processed_version: 1,
        processed_at: 8.days.ago
      )
      Analytics::RollupRefreshState.create!(
        analytics_site: site,
        bucket_start: Time.zone.parse("2026-04-04 09:00:00"),
        rollup_key: "site-page-hourly-rollup",
        request_version: 1,
        processed_version: 0,
        processed_at: nil
      )

      assert_difference -> { Analytics::RollupRefreshState.count }, -1 do
        Analytics::CleanupRollupRefreshStatesJob.perform_now
      end
    end
  end
end
