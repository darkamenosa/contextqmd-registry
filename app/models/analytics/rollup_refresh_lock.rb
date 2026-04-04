# frozen_string_literal: true

require "digest"

class Analytics::RollupRefreshLock
  def initialize(record_class:, rollup_key:)
    @record_class = record_class
    @rollup_key = rollup_key
  end

  def with_lock(site_id:, bucket_start:)
    record_class.transaction do
      if acquired?(site_id:, bucket_start:)
        yield
        true
      else
        false
      end
    end
  end

  def lock_id(site_id:, bucket_start:)
    digest = Digest::SHA256.digest([ rollup_key, site_id, bucket_start.to_i ].join(":"))
    value = digest.unpack1("q>")

    if value.zero?
      1
    else
      value
    end
  end

  private
    attr_reader :record_class, :rollup_key

    def acquired?(site_id:, bucket_start:)
      sql = "SELECT pg_try_advisory_xact_lock(#{record_class.connection.quote(lock_id(site_id:, bucket_start:))})"
      ActiveModel::Type::Boolean.new.cast(record_class.connection.select_value(sql))
    end
end
