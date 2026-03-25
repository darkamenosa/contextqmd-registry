# frozen_string_literal: true

require "test_helper"

class DocsFetcher::WebsiteScopeTest < ActiveSupport::TestCase
  test "website runner requests website-scoped proxies" do
    fetcher = DocsFetcher::Website::RubyRunner.new
    scope_seen = nil
    session_key_seen = nil
    target_host_seen = nil
    sticky_session_seen = nil
    crawl_request = Struct.new(:url, :id, :library_id, :library, :metadata).new(
      "https://example.com/guide",
      123,
      nil,
      nil,
      {}
    )

    original_checkout = ProxyPool.method(:checkout)

    ProxyPool.define_singleton_method(:checkout) do |scope:, target_host:, session_key:, sticky_session:|
      scope_seen = scope
      target_host_seen = target_host
      session_key_seen = session_key
      sticky_session_seen = sticky_session
      nil
    end

    fetcher.send(:setup_crawl_context, crawl_request, URI("https://example.com/guide"))

    assert_equal "website", scope_seen
    assert_equal "example.com", target_host_seen
    assert_equal "website:123", session_key_seen
    assert_equal true, sticky_session_seen
  ensure
    ProxyPool.define_singleton_method(:checkout, original_checkout)
  end
end
