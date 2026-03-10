# frozen_string_literal: true

require "test_helper"

class ProxyPoolTest < ActiveSupport::TestCase # rubocop:disable Minitest/TestFileName
  test "returns nil when no proxies configured" do
    assert_nil ProxyPool.next_proxy
    assert_equal 0, ProxyPool.size
  end

  test "returns proxy URI from DB config" do
    CrawlProxyConfig.create!(
      name: "test-proxy", scheme: "http", host: "proxy1.example.com", port: 8080
    )

    proxy = ProxyPool.next_proxy
    assert_equal "proxy1.example.com", proxy.host
    assert_equal 8080, proxy.port
    assert_equal 1, ProxyPool.size
  end

  test "skips proxies on cooldown" do
    CrawlProxyConfig.create!(
      name: "cooled", scheme: "http", host: "cool.example.com", port: 8080,
      cooldown_until: 1.hour.from_now
    )
    CrawlProxyConfig.create!(
      name: "ready", scheme: "http", host: "ready.example.com", port: 8080
    )

    proxy = ProxyPool.next_proxy
    assert_equal "ready.example.com", proxy.host
  end

  test "skips inactive proxies" do
    CrawlProxyConfig.create!(
      name: "inactive", scheme: "http", host: "off.example.com", port: 8080,
      active: false
    )

    assert_nil ProxyPool.next_proxy
    assert_equal 0, ProxyPool.size
  end

  test "filters by usage scope" do
    CrawlProxyConfig.create!(
      name: "website-only", scheme: "http", host: "web.example.com", port: 8080,
      usage_scope: "website"
    )
    CrawlProxyConfig.create!(
      name: "all-scope", scheme: "http", host: "all.example.com", port: 8080,
      usage_scope: "all"
    )

    # "structured" scope should only match "all" scope proxies
    proxy = ProxyPool.next_proxy(scope: "structured")
    assert_equal "all.example.com", proxy.host
  end

  test "prefers higher priority proxies" do
    CrawlProxyConfig.create!(
      name: "low", scheme: "http", host: "low.example.com", port: 8080,
      priority: 1
    )
    CrawlProxyConfig.create!(
      name: "high", scheme: "http", host: "high.example.com", port: 8080,
      priority: 10
    )

    proxy = ProxyPool.next_proxy
    assert_equal "high.example.com", proxy.host
  end

  test "all_proxies returns all available proxies" do
    CrawlProxyConfig.create!(name: "p1", scheme: "http", host: "p1.example.com", port: 8080)
    CrawlProxyConfig.create!(name: "p2", scheme: "http", host: "p2.example.com", port: 9090)

    proxies = ProxyPool.all_proxies
    assert_equal 2, proxies.size
  end

  test "includes proxy credentials in URI" do
    CrawlProxyConfig.create!(
      name: "auth-proxy", scheme: "http", host: "auth.example.com", port: 8080,
      username: "user", password: "pass"
    )

    proxy = ProxyPool.next_proxy
    assert_equal "auth.example.com", proxy.host
    assert_equal "user", proxy.user
    assert_equal "pass", proxy.password
  end
end
