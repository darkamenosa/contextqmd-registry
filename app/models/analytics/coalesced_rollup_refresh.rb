# frozen_string_literal: true

module Analytics::CoalescedRollupRefresh
  extend ActiveSupport::Concern

  class_methods do
    def refresh_later(site:, bucket_start:)
      enqueue_coalesced_refresh_job(site:, bucket_start:, job_class: refresh_job_class)
    end

    def perform_coalesced_refresh(site:, bucket_start:)
      perform_coalesced_refresh_job(site:, bucket_start:, job_class: refresh_job_class)
    end

    def enqueue_coalesced_refresh_job(site:, bucket_start:, job_class:)
      if available?
        site_id = normalize_site_id(site)
        bucket = bucket_start_for(bucket_start)

        if site_id.present? && bucket.present?
          mark_refresh_dirty(site_id:, bucket_start: bucket)

          if should_enqueue_refresh?(site_id:, bucket_start: bucket)
            job_class.perform_later(site_id, bucket)
          end
        end
      end
    end

    def perform_coalesced_refresh_job(site:, bucket_start:, job_class:)
      if available?
        site_id = normalize_site_id(site)
        bucket = bucket_start_for(bucket_start)

        if site_id.present? && bucket.present?
          begin
            loop do
              clear_refresh_dirty(site_id:, bucket_start: bucket)
              refresh_bucket!(site: site_id, bucket_start: bucket)
              break unless refresh_dirty?(site_id:, bucket_start: bucket)
            end
          ensure
            release_refresh_claim(site_id:, bucket_start: bucket)

            if refresh_dirty?(site_id:, bucket_start: bucket) &&
                should_enqueue_refresh?(site_id:, bucket_start: bucket)
              job_class.perform_later(site_id, bucket)
            end
          end
        end
      end
    end

    private
      def should_enqueue_refresh?(site_id:, bucket_start:)
        return true unless cache_available?

        Rails.cache.write(
          refresh_claim_cache_key(site_id:, bucket_start:),
          true,
          unless_exist: true,
          expires_in: refresh_claim_ttl
        )
      rescue StandardError
        true
      end

      def mark_refresh_dirty(site_id:, bucket_start:)
        return unless cache_available?

        Rails.cache.write(refresh_dirty_cache_key(site_id:, bucket_start:), true, expires_in: refresh_dirty_ttl)
      rescue StandardError
        nil
      end

      def clear_refresh_dirty(site_id:, bucket_start:)
        return unless cache_available?

        Rails.cache.delete(refresh_dirty_cache_key(site_id:, bucket_start:))
      rescue StandardError
        nil
      end

      def refresh_dirty?(site_id:, bucket_start:)
        return false unless cache_available?

        Rails.cache.exist?(refresh_dirty_cache_key(site_id:, bucket_start:))
      rescue StandardError
        false
      end

      def release_refresh_claim(site_id:, bucket_start:)
        return unless cache_available?

        Rails.cache.delete(refresh_claim_cache_key(site_id:, bucket_start:))
      rescue StandardError
        nil
      end

      def refresh_claim_cache_key(site_id:, bucket_start:)
        [ "analytics", refresh_cache_namespace, "scheduled", site_id, bucket_start.to_i ].join(":")
      end

      def refresh_dirty_cache_key(site_id:, bucket_start:)
        [ "analytics", refresh_cache_namespace, "dirty", site_id, bucket_start.to_i ].join(":")
      end

      def refresh_cache_namespace
        name.demodulize.underscore.tr("_", "-")
      end

      def refresh_claim_ttl
        if const_defined?(:COALESCE_WINDOW, false)
          self::COALESCE_WINDOW * 5
        else
          5.minutes
        end
      end

      def refresh_dirty_ttl
        5.minutes
      end

      def refresh_job_class
        "Analytics::#{name.demodulize}RefreshJob".constantize
      end

      def cache_available?
        !Rails.cache.is_a?(ActiveSupport::Cache::NullStore)
      rescue StandardError
        false
      end
  end
end
