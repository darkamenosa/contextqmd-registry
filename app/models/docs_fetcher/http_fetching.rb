# frozen_string_literal: true

require "net/http"

module DocsFetcher
  module HttpFetching
    private

      def http_get(
        uri,
        redirect_limit: 5,
        raise_on_error: false,
        scope: proxy_scope,
        proxy_lease: nil,
        accept: nil,
        user_agent: nil,
        open_timeout: 10,
        read_timeout: 30,
        max_size: nil,
        oversize: :truncate,
        allowed_content_types: nil
      )
        if redirect_limit <= 0
          return nil unless raise_on_error

          raise DocsFetcher::TransientFetchError, "Too many redirects for #{uri}"
        end

        proxy_target = proxy_lease || ProxyPool.next_proxy_config(scope: scope, target_host: uri.host)
        proxy_config = proxy_target&.respond_to?(:crawl_proxy_config) ? proxy_target.crawl_proxy_config : proxy_target
        response = perform_http_get(
          uri,
          proxy_config,
          accept: accept,
          user_agent: user_agent,
          open_timeout: open_timeout,
          read_timeout: read_timeout
        )
        record_proxy_success(proxy_target, uri)

        if response.is_a?(Net::HTTPRedirection) && response["location"]
          redirect_uri = URI.join(uri, response["location"])
          unless SsrfGuard.safe_uri?(redirect_uri)
            return nil unless raise_on_error

            raise DocsFetcher::PermanentFetchError, "Redirect to private address: #{redirect_uri.host}"
          end

          return http_get(
            redirect_uri,
            redirect_limit: redirect_limit - 1,
            raise_on_error: raise_on_error,
            scope: scope,
            proxy_lease: proxy_lease,
            accept: accept,
            user_agent: user_agent,
            open_timeout: open_timeout,
            read_timeout: read_timeout,
            max_size: max_size,
            oversize: oversize,
            allowed_content_types: allowed_content_types
          )
        end

        unless response.is_a?(Net::HTTPSuccess)
          return nil unless raise_on_error

          raise_for_http_error!(uri, response)
        end

        content_type = response["content-type"].to_s
        if allowed_content_types.present?
          content_type_allowed = content_type.empty? ||
            allowed_content_types.any? { |allowed| content_type.include?(allowed) }
          return nil unless content_type_allowed
        end

        body = response.body.to_s.dup.force_encoding("UTF-8")
        return body unless max_size && body.bytesize > max_size

        case oversize
        when :truncate
          body.byteslice(0, max_size)
        when :nil
          nil
        else
          body
        end
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED,
             Errno::ECONNRESET, SocketError, OpenSSL::SSL::SSLError => error
        record_proxy_failure(proxy_target, uri, error)
        raise DocsFetcher::TransientFetchError, "Network error fetching #{uri}: #{error.message}" if raise_on_error

        nil
      end

      def proxy_scope
        "structured"
      end

      def perform_http_get(uri, proxy_config, accept:, user_agent:, open_timeout:, read_timeout:)
        proxy = proxy_config&.to_uri
        http = Net::HTTP.new(
          uri.hostname,
          uri.port,
          proxy&.host,
          proxy&.port,
          proxy&.user,
          proxy&.password
        )
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = open_timeout
        http.read_timeout = read_timeout

        request = Net::HTTP::Get.new(uri)
        request["Accept"] = accept if accept.present?
        request["User-Agent"] = user_agent if user_agent.present?
        http.request(request)
      end

      def raise_for_http_error!(uri, response)
        code = response.code.to_i

        case code
        when 429
          raise DocsFetcher::RateLimitError, "Rate limited (429) fetching #{uri}"
        when 404, 410
          raise DocsFetcher::PermanentFetchError, "Not found (#{code}) fetching #{uri}"
        when 500..599
          raise DocsFetcher::TransientFetchError, "Server error (#{code}) fetching #{uri}"
        else
          raise DocsFetcher::PermanentFetchError, "HTTP #{code} fetching #{uri}"
        end
      end

      def record_proxy_success(proxy_config, uri)
        proxy_config&.record_success(target_host: uri.host)
      end

      def record_proxy_failure(proxy_config, uri, error)
        proxy_config&.record_failure(error_class: error.class.name, target_host: uri.host)
      end
  end
end
