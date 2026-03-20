# frozen_string_literal: true

require "test_helper"

class DocsFetcher::WebsiteScopeTest < ActiveSupport::TestCase
  test "website runner requests website-scoped proxies" do
    fetcher = DocsFetcher::Website::RubyRunner.new
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.define_singleton_method(:body) { "<html><body>Hello</body></html>" }
    response.define_singleton_method(:[]) { |key| key == "content-type" ? "text/html" : nil }

    http = Class.new do
      attr_accessor :use_ssl, :open_timeout, :read_timeout

      def initialize(response)
        @response = response
      end

      def request(_request)
        @response
      end
    end.new(response)

    scope_seen = nil
    original_proxy_lookup = ProxyPool.method(:next_proxy_config)
    original_http_new = Net::HTTP.method(:new)

    ProxyPool.define_singleton_method(:next_proxy_config) do |scope: "all", target_host: nil, sticky_session: false|
      scope_seen = scope
      nil
    end
    Net::HTTP.define_singleton_method(:new) { |*_args| http }

    fetcher.send(:http_get_with_redirects, URI("https://example.com/guide"))

    assert_equal "website", scope_seen
  ensure
    ProxyPool.define_singleton_method(:next_proxy_config, original_proxy_lookup)
    Net::HTTP.define_singleton_method(:new, original_http_new)
  end
end
