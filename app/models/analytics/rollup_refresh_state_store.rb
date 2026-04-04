# frozen_string_literal: true

class Analytics::RollupRefreshStateStore
  def initialize(rollup_key:, relation: Analytics::RollupRefreshState)
    @relation = relation
    @rollup_key = rollup_key
  end

  def mark_requested!(site_id:, bucket_start:)
    now = Time.current
    updated = scoped_row(site_id:, bucket_start:).update_all([ "request_version = request_version + 1, updated_at = ?", now ])

    if updated.zero?
      relation.create!(
        analytics_site_id: site_id,
        bucket_start: bucket_start,
        rollup_key: rollup_key,
        request_version: 1,
        processed_version: 0,
        created_at: now,
        updated_at: now
      )
    end
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def try_enqueue!(site_id:, bucket_start:, stale_before:)
    now = Time.current
    scoped_row(site_id:, bucket_start:)
      .where("request_version > processed_version")
      .where("enqueued_at IS NULL OR enqueued_at < ?", stale_before)
      .update_all(enqueued_at: now, updated_at: now)
      .positive?
  end

  def pending_request_version(site_id:, bucket_start:)
    request_version, processed_version = scoped_row(site_id:, bucket_start:)
      .pick(:request_version, :processed_version)
    return if request_version.blank?
    return unless request_version > processed_version.to_i

    request_version.to_i
  end

  def pending?(site_id:, bucket_start:)
    pending_request_version(site_id:, bucket_start:).present?
  end

  def mark_processed!(site_id:, bucket_start:, processed_version:)
    now = Time.current
    scoped_row(site_id:, bucket_start:)
      .where("processed_version < ?", processed_version)
      .update_all(processed_version: processed_version, processed_at: now, updated_at: now)
  end

  def clear_enqueue!(site_id:, bucket_start:)
    now = Time.current
    scoped_row(site_id:, bucket_start:)
      .where.not(enqueued_at: nil)
      .update_all(enqueued_at: nil, updated_at: now)
  end

  private
    attr_reader :relation, :rollup_key

    def scoped_row(site_id:, bucket_start:)
      relation.where(
        analytics_site_id: site_id,
        bucket_start: bucket_start,
        rollup_key: rollup_key
      )
    end
end
