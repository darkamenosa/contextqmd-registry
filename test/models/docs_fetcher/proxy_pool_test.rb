# frozen_string_literal: true

require "test_helper"

class DocsFetcher::ProxyPoolTest < ActiveSupport::TestCase
  teardown do
    ENV.delete("CRAWL_PROXY_URL")
    ENV.delete("CRAWL_PROXY_URLS")
    DocsFetcher::ProxyPool.reset!
  end

  test "returns nil when no proxies configured" do
    DocsFetcher::ProxyPool.reset!
    assert_nil DocsFetcher::ProxyPool.next_proxy
    assert_equal 0, DocsFetcher::ProxyPool.size
  end

  test "uses single proxy from CRAWL_PROXY_URL" do
    ENV["CRAWL_PROXY_URL"] = "http://proxy1.example.com:8080"
    DocsFetcher::ProxyPool.reset!

    proxy = DocsFetcher::ProxyPool.next_proxy
    assert_equal "proxy1.example.com", proxy.host
    assert_equal 8080, proxy.port
    assert_equal 1, DocsFetcher::ProxyPool.size
  end

  test "rotates through multiple proxies from CRAWL_PROXY_URLS" do
    ENV["CRAWL_PROXY_URLS"] = "http://p1:8080,http://p2:8080,http://p3:8080"
    DocsFetcher::ProxyPool.reset!

    assert_equal 3, DocsFetcher::ProxyPool.size

    hosts = 6.times.map { DocsFetcher::ProxyPool.next_proxy.host }
    assert_equal %w[p1 p2 p3 p1 p2 p3], hosts
  end

  test "CRAWL_PROXY_URLS takes priority over CRAWL_PROXY_URL" do
    ENV["CRAWL_PROXY_URL"] = "http://single:8080"
    ENV["CRAWL_PROXY_URLS"] = "http://pool1:8080,http://pool2:8080"
    DocsFetcher::ProxyPool.reset!

    assert_equal 2, DocsFetcher::ProxyPool.size
    assert_equal "pool1", DocsFetcher::ProxyPool.next_proxy.host
  end

  test "skips invalid proxy URLs in pool" do
    ENV["CRAWL_PROXY_URLS"] = "http://valid:8080,not a url,http://also-valid:9090"
    DocsFetcher::ProxyPool.reset!

    assert_equal 2, DocsFetcher::ProxyPool.size
  end

  test "handles proxy with authentication" do
    ENV["CRAWL_PROXY_URL"] = "http://user:pass@proxy.example.com:8080"
    DocsFetcher::ProxyPool.reset!

    proxy = DocsFetcher::ProxyPool.next_proxy
    assert_equal "proxy.example.com", proxy.host
    assert_equal "user", proxy.user
    assert_equal "pass", proxy.password
  end

  test "handles empty CRAWL_PROXY_URLS" do
    ENV["CRAWL_PROXY_URLS"] = ""
    DocsFetcher::ProxyPool.reset!

    assert_equal 0, DocsFetcher::ProxyPool.size
    assert_nil DocsFetcher::ProxyPool.next_proxy
  end

  test "handles whitespace in proxy list" do
    ENV["CRAWL_PROXY_URLS"] = " http://p1:8080 , http://p2:8080 , "
    DocsFetcher::ProxyPool.reset!

    assert_equal 2, DocsFetcher::ProxyPool.size
    assert_equal "p1", DocsFetcher::ProxyPool.next_proxy.host
  end

  test "reset! clears cached proxies and rotation index" do
    ENV["CRAWL_PROXY_URLS"] = "http://p1:8080,http://p2:8080"
    DocsFetcher::ProxyPool.reset!

    DocsFetcher::ProxyPool.next_proxy # advance to p2
    DocsFetcher::ProxyPool.reset!

    # After reset, starts from the beginning again
    assert_equal "p1", DocsFetcher::ProxyPool.next_proxy.host
  end

  test "all_proxies returns full list" do
    ENV["CRAWL_PROXY_URLS"] = "http://p1:8080,http://p2:8080"
    DocsFetcher::ProxyPool.reset!

    proxies = DocsFetcher::ProxyPool.all_proxies
    assert_equal 2, proxies.size
    assert_equal "p1", proxies[0].host
    assert_equal "p2", proxies[1].host
  end
end
