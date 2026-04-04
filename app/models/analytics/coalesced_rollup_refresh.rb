# frozen_string_literal: true

module Analytics::CoalescedRollupRefresh
  extend ActiveSupport::Concern

  class_methods do
    def refresh_later(site:, bucket_start:)
      if available?
        site_id = normalize_site_id(site)
        bucket = bucket_start_for(bucket_start)

        if site_id.present? && bucket.present?
          refresh_coordinator.enqueue(site_id:, bucket_start: bucket)
        end
      end
    end

    def perform_coalesced_refresh(site:, bucket_start:)
      if available?
        site_id = normalize_site_id(site)
        bucket = bucket_start_for(bucket_start)

        if site_id.present? && bucket.present?
          refresh_coordinator.perform(site_id:, bucket_start: bucket)
        end
      end
    end

    private
      def refresh_coordinator
        @refresh_coordinator ||= build_refresh_coordinator
      end

      def build_refresh_coordinator
        Analytics::RollupRefreshCoordinator.new(
          lock: Analytics::RollupRefreshLock.new(record_class: self, rollup_key: refresh_rollup_key),
          state_store: Analytics::RollupRefreshStateStore.new(rollup_key: refresh_rollup_key),
          refresher: ->(site_id:, bucket_start:) { refresh_bucket!(site: site_id, bucket_start:) },
          enqueue_job: ->(site_id, bucket_start) { refresh_job_class.perform_later(site_id, bucket_start) },
          claim_ttl: refresh_claim_ttl
        )
      end

      def refresh_rollup_key
        name.demodulize.underscore.tr("_", "-")
      end

      def refresh_claim_ttl
        15.minutes
      end

      def refresh_job_class
        "Analytics::#{name.demodulize}RefreshJob".constantize
      end
  end
end
