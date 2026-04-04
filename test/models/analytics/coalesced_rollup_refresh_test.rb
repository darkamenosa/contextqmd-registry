# frozen_string_literal: true

require "test_helper"

class Analytics::CoalescedRollupRefreshTest < ActiveSupport::TestCase
  test "refresh_later normalizes arguments and delegates to the coordinator" do
    coordinator = FakeCoordinator.new
    site = Analytics::Site.new(id: 42)
    bucket_start = Time.zone.parse("2026-03-25 09:15:00")

    with_stubbed_singleton_method(Analytics::SitePageHourlyRollup, :refresh_coordinator, coordinator) do
      Analytics::SitePageHourlyRollup.refresh_later(site:, bucket_start:)
    end

    assert_equal [ { site_id: 42, bucket_start: Time.zone.parse("2026-03-25 09:00:00") } ], coordinator.enqueue_calls
  end

  test "perform_coalesced_refresh normalizes arguments and delegates to the coordinator" do
    coordinator = FakeCoordinator.new
    bucket_start = Time.zone.parse("2026-03-25 09:45:00")

    with_stubbed_singleton_method(Analytics::SitePageHourlyRollup, :refresh_coordinator, coordinator) do
      Analytics::SitePageHourlyRollup.perform_coalesced_refresh(site: 7, bucket_start:)
    end

    assert_equal [ { site_id: 7, bucket_start: Time.zone.parse("2026-03-25 09:00:00") } ], coordinator.perform_calls
  end

  private
    class FakeCoordinator
      attr_reader :enqueue_calls, :perform_calls

      def initialize
        @enqueue_calls = []
        @perform_calls = []
      end

      def enqueue(**kwargs)
        enqueue_calls << kwargs
      end

      def perform(**kwargs)
        perform_calls << kwargs
      end
    end
end
