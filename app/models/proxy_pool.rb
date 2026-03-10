# frozen_string_literal: true

# Proxy selection layer for outbound HTTP requests.
# Delegates to CrawlProxyConfig (DB-backed proxy inventory with cooldown-based health).
#
# Usage:
#   proxy = ProxyPool.next_proxy
#   http = Net::HTTP.new(uri.host, uri.port, proxy&.host, proxy&.port, proxy&.user, proxy&.password)
class ProxyPool
  class << self
    # Returns the next proxy URI, or nil if none configured.
    def next_proxy(scope: "all")
      CrawlProxyConfig.next_proxy(scope: scope)
    end

    def all_proxies(scope: "all")
      CrawlProxyConfig.available_proxies(scope: scope)
    end

    def size
      CrawlProxyConfig.available.count
    end
  end
end
