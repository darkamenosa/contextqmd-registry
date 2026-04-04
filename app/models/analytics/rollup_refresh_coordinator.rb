# frozen_string_literal: true

class Analytics::RollupRefreshCoordinator
  def initialize(lock:, state_store:, refresher:, enqueue_job:, claim_ttl:)
    @lock = lock
    @state_store = state_store
    @refresher = refresher
    @enqueue_job = enqueue_job
    @claim_ttl = claim_ttl
  end

  def enqueue(site_id:, bucket_start:)
    state_store.mark_requested!(site_id:, bucket_start:)

    if state_store.try_enqueue!(site_id:, bucket_start:, stale_before: claim_ttl.ago)
      enqueue_job.call(site_id, bucket_start)
    end
  end

  def perform(site_id:, bucket_start:)
    lock.with_lock(site_id:, bucket_start:) do
      begin
        while (request_version = state_store.pending_request_version(site_id:, bucket_start:))
          refresher.call(site_id:, bucket_start:)
          state_store.mark_processed!(site_id:, bucket_start:, processed_version: request_version)
        end
      ensure
        state_store.clear_enqueue!(site_id:, bucket_start:)

        if state_store.pending?(site_id:, bucket_start:) &&
            state_store.try_enqueue!(site_id:, bucket_start:, stale_before: claim_ttl.ago)
          enqueue_job.call(site_id, bucket_start)
        end
      end
    end
  end

  private
    attr_reader :claim_ttl, :enqueue_job, :lock, :refresher, :state_store
end
