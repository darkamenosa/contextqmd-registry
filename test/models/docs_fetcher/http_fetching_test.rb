# frozen_string_literal: true

require "test_helper"

class DocsFetcher::HttpFetchingTest < ActiveSupport::TestCase
  class DummyFetcher
    include DocsFetcher::HttpFetching
  end

  test "http_get uses the requested proxy scope and records proxy success" do
    fetcher = DummyFetcher.new
    proxy_config = build_proxy_config
    response = build_success_response(body: "hello")
    http = build_http(response)
    scope_seen = nil

    original_proxy_lookup = ProxyPool.method(:next_proxy_config)
    original_http_new = Net::HTTP.method(:new)

    ProxyPool.define_singleton_method(:next_proxy_config) do |scope: "all"|
      scope_seen = scope
      proxy_config
    end
    Net::HTTP.define_singleton_method(:new) { |*_args| http }

    body = fetcher.send(
      :http_get,
      URI("https://docs.example.com/guide"),
      scope: "structured",
      raise_on_error: true
    )

    assert_equal "hello", body

    assert_equal "structured", scope_seen
    assert_equal [ "docs.example.com" ], proxy_config.successes
    assert_empty proxy_config.failures
  ensure
    ProxyPool.define_singleton_method(:next_proxy_config, original_proxy_lookup)
    Net::HTTP.define_singleton_method(:new, original_http_new)
  end

  test "http_get records proxy failure on network errors" do
    fetcher = DummyFetcher.new
    proxy_config = build_proxy_config
    http = build_http(Net::OpenTimeout.new("timed out"))

    original_proxy_lookup = ProxyPool.method(:next_proxy_config)
    original_http_new = Net::HTTP.method(:new)

    ProxyPool.define_singleton_method(:next_proxy_config) { |**_opts| proxy_config }
    Net::HTTP.define_singleton_method(:new) { |*_args| http }

    assert_nil fetcher.send(
      :http_get,
      URI("https://docs.example.com/guide"),
      scope: "website",
      raise_on_error: false
    )

    assert_empty proxy_config.successes
    assert_equal [ [ "Net::OpenTimeout", "docs.example.com" ] ], proxy_config.failures
  ensure
    ProxyPool.define_singleton_method(:next_proxy_config, original_proxy_lookup)
    Net::HTTP.define_singleton_method(:new, original_http_new)
  end

  private

    def build_success_response(body:)
      response = Net::HTTPOK.new("1.1", "200", "OK")
      response.define_singleton_method(:body) { body }
      response.define_singleton_method(:[]) { |_key| nil }
      response
    end

    def build_http(result)
      Class.new do
        attr_accessor :use_ssl, :open_timeout, :read_timeout

        define_method(:initialize) do |result|
          @result = result
        end

        define_method(:request) do |_request|
          raise @result if @result.is_a?(Exception)

          @result
        end
      end.new(result)
    end

    def build_proxy_config
      Struct.new(:successes, :failures) do
        def to_uri
          URI("http://proxy.example.com:8080")
        end

        def record_success(target_host: nil)
          successes << target_host
        end

        def record_failure(error_class: nil, target_host: nil)
          failures << [ error_class, target_host ]
        end
      end.new([], [])
    end
end
