# frozen_string_literal: true

# DB-backed proxy inventory for crawl requests.
# Replaces env-based proxy selection with configurable, health-tracked proxies.
#
# Selection uses cooldown-based health, not dead/alive logic:
# - first failure: record it
# - repeated failures: increase cooldown
# - auth/config failures: disable config
# - operators manually reactivate
class CrawlProxyConfig < ApplicationRecord
  SCHEMES = %w[http https socks5].freeze
  KINDS = %w[datacenter residential mobile].freeze
  SCOPES = %w[website structured all].freeze

  validates :name, presence: true
  validates :scheme, presence: true, inclusion: { in: SCHEMES }
  validates :host, presence: true
  validates :port, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :kind, inclusion: { in: KINDS }, allow_nil: true
  validates :usage_scope, inclusion: { in: SCOPES }

  scope :active, -> { where(active: true) }
  scope :available, -> { active.where("cooldown_until IS NULL OR cooldown_until < ?", Time.current) }
  scope :for_scope, ->(scope) { where(usage_scope: [ scope, "all" ]) }
  scope :by_priority, -> { order(priority: :desc, consecutive_failures: :asc) }

  # Returns a proxy URI suitable for Net::HTTP, or nil if none available.
  # Prefers higher priority, lower failure count, and provider diversity.
  def self.next_proxy(scope: "all")
    config = available.for_scope(scope).by_priority.first
    config&.to_uri
  end

  # Returns all available proxy URIs for a given scope.
  def self.available_proxies(scope: "all")
    available.for_scope(scope).by_priority.map(&:to_uri)
  end

  def to_uri
    userinfo = username.present? ? "#{username}:#{password}@" : ""
    URI.parse("#{scheme}://#{userinfo}#{host}:#{port}")
  end

  # Record a successful use of this proxy.
  def record_success(target_host: nil)
    update!(
      consecutive_failures: 0,
      cooldown_until: nil,
      last_success_at: Time.current,
      last_target_host: target_host
    )
  end

  # Record a failure and apply cooldown if needed.
  def record_failure(error_class: nil, target_host: nil)
    new_failures = consecutive_failures + 1
    cooldown = compute_cooldown(new_failures)

    update!(
      consecutive_failures: new_failures,
      cooldown_until: cooldown ? Time.current + cooldown : nil,
      last_failure_at: Time.current,
      last_error_class: error_class,
      last_target_host: target_host
    )
  end

  private

    # Exponential backoff: 30s, 2m, 10m, 30m, 1h
    def compute_cooldown(failures)
      case failures
      when 1 then 30.seconds
      when 2 then 2.minutes
      when 3 then 10.minutes
      when 4 then 30.minutes
      else 1.hour
      end
    end
end
