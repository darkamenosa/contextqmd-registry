# frozen_string_literal: true

class CrawlProxyLease < ApplicationRecord
  belongs_to :crawl_proxy_config

  validates :session_key, presence: true
  validates :usage_scope, inclusion: { in: CrawlProxyConfig::SCOPES }
  validates :expires_at, presence: true
  validates :last_seen_at, presence: true

  scope :unreleased, -> { where(released_at: nil) }
  scope :active, -> { unreleased.where("expires_at > ?", Time.current) }
  scope :for_scope, ->(scope) { where(usage_scope: scope) }

  def expired?
    expires_at <= Time.current
  end

  def active?
    released_at.nil? && !expired?
  end

  def release!
    return if released_at.present?

    update!(released_at: Time.current)
  end

  def touch_lease!
    now = Time.current
    update!(
      last_seen_at: now,
      expires_at: now + crawl_proxy_config.lease_ttl
    )
  end

  def record_success(target_host: nil)
    touch_lease!
    crawl_proxy_config.record_success(target_host: target_host)
  end

  def record_failure(error_class: nil, target_host: nil)
    touch_lease!
    crawl_proxy_config.record_failure(error_class: error_class, target_host: target_host)
  end
end
