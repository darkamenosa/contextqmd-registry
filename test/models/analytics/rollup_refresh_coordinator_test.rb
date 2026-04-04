# frozen_string_literal: true

require "test_helper"

class Analytics::RollupRefreshCoordinatorTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    build_coordinator
  end

  test "enqueue records requested work and schedules one job" do
    travel_to Time.zone.parse("2026-03-25 09:00:00") do
      coordinator.enqueue(site_id: 1, bucket_start: bucket_start)

      assert_equal [ { site_id: 1, bucket_start: bucket_start } ], state_store.mark_requested_calls
      assert_equal [ { site_id: 1, bucket_start: bucket_start, stale_before: Time.zone.parse("2026-03-25 08:45:00") } ], state_store.try_enqueue_calls
      assert_equal [ [ 1, bucket_start ] ], enqueued_jobs
    end
  end

  test "perform processes each pending version and clears the enqueue marker" do
    state_store.pending_versions = [ 1, 2, nil ]
    state_store.pending = false

    coordinator.perform(site_id: 1, bucket_start: bucket_start)

    assert_equal [ { site_id: 1, bucket_start: bucket_start } ], lock.calls
    assert_equal [ { site_id: 1, bucket_start: bucket_start }, { site_id: 1, bucket_start: bucket_start } ], refreshed_buckets
    assert_equal [ 1, 2 ], state_store.mark_processed_calls.map { |entry| entry.fetch(:processed_version) }
    assert_equal [ { site_id: 1, bucket_start: bucket_start } ], state_store.clear_enqueue_calls
    assert_empty enqueued_jobs
  end

  test "perform re-enqueues when work arrives after the current pass" do
    travel_to Time.zone.parse("2026-03-25 09:00:00") do
      state_store.pending_versions = [ 1, nil ]
      state_store.pending = true
      state_store.try_enqueue_results = [ true ]

      coordinator.perform(site_id: 1, bucket_start: bucket_start)

      assert_equal [ [ 1, bucket_start ] ], enqueued_jobs
      assert_equal [ { site_id: 1, bucket_start: bucket_start, stale_before: Time.zone.parse("2026-03-25 08:45:00") } ], state_store.try_enqueue_calls
    end
  end

  test "perform does nothing when the lock is not acquired" do
    lock.locked = false

    coordinator.perform(site_id: 1, bucket_start: bucket_start)

    assert_equal [ { site_id: 1, bucket_start: bucket_start } ], lock.calls
    assert_empty refreshed_buckets
    assert_empty state_store.mark_processed_calls
    assert_empty state_store.clear_enqueue_calls
  end

  private
    attr_reader :coordinator, :enqueued_jobs, :lock, :refreshed_buckets, :state_store

    def bucket_start
      @bucket_start ||= Time.zone.parse("2026-03-25 09:00:00")
    end

    def build_coordinator
      @lock = FakeLock.new
      @state_store = FakeStateStore.new
      @refreshed_buckets = []
      @enqueued_jobs = []

      @coordinator = Analytics::RollupRefreshCoordinator.new(
        lock: lock,
        state_store: state_store,
        refresher: ->(**kwargs) { refreshed_buckets << kwargs },
        enqueue_job: ->(*args) { enqueued_jobs << args },
        claim_ttl: 15.minutes
      )
    end

    class FakeLock
      attr_accessor :locked
      attr_reader :calls

      def initialize
        @calls = []
        @locked = true
      end

      def with_lock(**kwargs)
        calls << kwargs
        return false unless locked

        yield
        true
      end
    end

    class FakeStateStore
      attr_accessor :pending, :pending_versions, :try_enqueue_results
      attr_reader :clear_enqueue_calls, :mark_processed_calls, :mark_requested_calls, :try_enqueue_calls

      def initialize
        @clear_enqueue_calls = []
        @mark_processed_calls = []
        @mark_requested_calls = []
        @pending = false
        @pending_versions = []
        @try_enqueue_calls = []
        @try_enqueue_results = [ true ]
      end

      def mark_requested!(**kwargs)
        mark_requested_calls << kwargs
      end

      def try_enqueue!(**kwargs)
        try_enqueue_calls << kwargs
        try_enqueue_results.shift
      end

      def pending_request_version(**_kwargs)
        pending_versions.shift
      end

      def mark_processed!(**kwargs)
        mark_processed_calls << kwargs
      end

      def clear_enqueue!(**kwargs)
        clear_enqueue_calls << kwargs
      end

      def pending?(**_kwargs)
        pending
      end
    end
end
