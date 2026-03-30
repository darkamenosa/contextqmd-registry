# frozen_string_literal: true

class Analytics::Bootstrap
  ADVISORY_LOCK_KEY = 42_674_001

  class << self
    def ensure_default_site!(host:, name: nil)
      normalized_host = Analytics::SiteBoundary.normalize_host(host)
      raise ArgumentError, "host is required" if normalized_host.blank?
      normalized_name = name.to_s.strip.presence || normalized_host

      Analytics::Site.transaction do
        Analytics::Site.connection.execute("SELECT pg_advisory_xact_lock(#{ADVISORY_LOCK_KEY})")

        existing = Analytics::Site.active.order(:id).first
        if existing.present?
          if existing.name != normalized_name
            existing.update!(name: normalized_name)
          end
          return existing
        end

        Analytics::Site.create!(
          name: normalized_name,
          canonical_hostname: normalized_host,
          status: Analytics::Site::STATUS_ACTIVE,
          metadata: {}
        )
      end
    end
  end
end
