# frozen_string_literal: true

# Proxy selection layer for outbound HTTP requests.
# Delegates to CrawlProxyConfig (DB-backed proxy inventory with cooldown-based health).
#
# Usage:
#   proxy = ProxyPool.next_proxy
#   http = Net::HTTP.new(uri.host, uri.port, proxy&.host, proxy&.port, proxy&.user, proxy&.password)
class ProxyPool
  class << self
    def checkout(scope: "all", target_host: nil, session_key:, sticky_session: false)
      existing_lease = reusable_lease(scope: scope, session_key: session_key)
      return existing_lease if existing_lease

      candidate_configs(scope: scope, target_host: target_host, sticky_session: sticky_session).each do |candidate|
        lease = checkout_candidate(
          candidate,
          scope: scope,
          target_host: target_host,
          session_key: session_key,
          sticky_session: sticky_session
        )
        return lease if lease
      end

      nil
    rescue ActiveRecord::RecordNotUnique
      reusable_lease(scope: scope, session_key: session_key)
    end

    def next_proxy_config(scope: "all", target_host: nil, sticky_session: false)
      candidate_configs(
        scope: scope,
        target_host: target_host,
        sticky_session: sticky_session
      ).first
    end

    # Returns the next proxy URI, or nil if none configured.
    def next_proxy(scope: "all", target_host: nil, sticky_session: false)
      next_proxy_config(
        scope: scope,
        target_host: target_host,
        sticky_session: sticky_session
      )&.to_uri
    end

    def all_proxies(scope: "all", target_host: nil, sticky_session: false)
      candidate_configs(
        scope: scope,
        target_host: target_host,
        sticky_session: sticky_session
      ).map(&:to_uri)
    end

    def size
      CrawlProxyConfig.available.count
    end

    private

      def reusable_lease(scope:, session_key:)
        return if session_key.blank?

        lease = CrawlProxyLease.unreleased
          .for_scope(scope)
          .includes(:crawl_proxy_config)
          .find_by(session_key: session_key)
        return unless lease

        if lease.expired? || !lease.crawl_proxy_config&.active?
          lease.release!
          return
        end

        lease.touch_lease!
        lease
      end

      def candidate_configs(scope:, target_host:, sticky_session:)
        configs = CrawlProxyConfig.available.for_scope(scope).to_a
        return [] if configs.empty?

        active_counts = CrawlProxyLease.active
          .where(crawl_proxy_config_id: configs.map(&:id))
          .group(:crawl_proxy_config_id)
          .count

        configs
          .select { |config| active_counts.fetch(config.id, 0) < config.max_concurrency }
          .sort_by do |config|
            [
              -config.priority,
              sticky_session ? sticky_session_penalty(config) : 0,
              active_counts.fetch(config.id, 0),
              config.consecutive_failures,
              config.last_success_at ? -config.last_success_at.to_i : Float::INFINITY,
              config.id
            ]
          end
      end

      def sticky_session_penalty(config)
        config.supports_sticky_sessions? ? 0 : 1
      end

      def checkout_candidate(candidate, scope:, target_host:, session_key:, sticky_session:)
        candidate.with_lock do
          candidate.reload
          return unless candidate.available_for_checkout?

          candidate.crawl_proxy_leases.create!(
            usage_scope: scope,
            session_key: session_key,
            target_host: target_host,
            sticky_session: sticky_session,
            last_seen_at: Time.current,
            expires_at: Time.current + candidate.lease_ttl,
            metadata: {}
          )
        end
      end
  end
end
