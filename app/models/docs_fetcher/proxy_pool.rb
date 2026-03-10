# frozen_string_literal: true

module DocsFetcher
  # Manages a pool of HTTP proxies for crawling.
  # Proxies rotate on each request to distribute load and avoid IP blocks.
  #
  # Configuration via environment variables:
  #   CRAWL_PROXY_URL  - single proxy (backwards compatible)
  #   CRAWL_PROXY_URLS - comma-separated list for rotation
  #
  # Examples:
  #   CRAWL_PROXY_URL=http://user:pass@proxy1.example.com:8080
  #   CRAWL_PROXY_URLS=http://proxy1:8080,http://proxy2:8080,socks5://proxy3:1080
  #
  # Usage in fetchers:
  #   proxy = DocsFetcher::ProxyPool.next_proxy
  #   http = Net::HTTP.new(uri.host, uri.port, proxy&.host, proxy&.port, proxy&.user, proxy&.password)
  class ProxyPool
    @mutex = Mutex.new
    @index = 0

    class << self
      # Returns the next proxy URI from the pool, or nil if no proxies configured.
      # Thread-safe round-robin rotation.
      def next_proxy
        proxies = parsed_proxies
        return nil if proxies.empty?

        @mutex.synchronize do
          proxy = proxies[@index % proxies.size]
          @index += 1
          proxy
        end
      end

      # Returns all configured proxy URIs.
      def all_proxies
        parsed_proxies
      end

      # Returns the number of configured proxies.
      def size
        parsed_proxies.size
      end

      # Reset the rotation index (useful for testing).
      def reset!
        @mutex.synchronize do
          @index = 0
          @parsed_proxies = nil
        end
      end

      private

        def parsed_proxies
          @parsed_proxies ||= load_proxies
        end

        def load_proxies
          urls = if ENV["CRAWL_PROXY_URLS"].present?
            ENV["CRAWL_PROXY_URLS"].split(",").map(&:strip).reject(&:empty?)
          elsif ENV["CRAWL_PROXY_URL"].present?
            [ ENV["CRAWL_PROXY_URL"].strip ]
          else
            []
          end

          urls.filter_map do |url|
            URI.parse(url)
          rescue URI::InvalidURIError
            Rails.logger.warn("Invalid proxy URL in pool: #{url}")
            nil
          end
        end
    end
  end
end
