# frozen_string_literal: true

require "test_helper"

class Analytics::RollupRefreshLockTest < ActiveSupport::TestCase
  test "lock ids are stable per rollup and bucket" do
    bucket_start = Time.zone.parse("2026-03-25 09:00:00")
    page_lock = Analytics::RollupRefreshLock.new(record_class: Analytics::SitePageHourlyRollup, rollup_key: "site-page-hourly-rollup")
    source_lock = Analytics::RollupRefreshLock.new(record_class: Analytics::SitePageHourlyRollup, rollup_key: "site-source-hourly-rollup")

    assert_equal page_lock.lock_id(site_id: 1, bucket_start: bucket_start), page_lock.lock_id(site_id: 1, bucket_start: bucket_start)
    assert_not_equal page_lock.lock_id(site_id: 1, bucket_start: bucket_start), page_lock.lock_id(site_id: 1, bucket_start: bucket_start + 1.hour)
    assert_not_equal page_lock.lock_id(site_id: 1, bucket_start: bucket_start), source_lock.lock_id(site_id: 1, bucket_start: bucket_start)
    assert_not_equal 0, page_lock.lock_id(site_id: 1, bucket_start: bucket_start)
  end
end
