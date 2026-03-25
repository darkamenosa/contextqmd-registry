# frozen_string_literal: true

require "test_helper"

class FaviconProxyTest < ActionDispatch::IntegrationTest
  test "proxies favicon requests through the app" do
    payload = {
      body: "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>",
      headers: {
        "content-type" => [ "image/x-icon" ],
        "cache-control" => [ "public, max-age=60" ]
      }
    }

    with_stubbed_favicon_fetch(payload) do
      get "/favicon/sources/ChatGPT"
    end

    assert_response :success
    assert_equal "image/svg+xml", response.headers["Content-Type"]
    assert_equal "script-src 'none'", response.headers["Content-Security-Policy"]
    assert_match(/attachment/, response.headers["Content-Disposition"])
    assert_equal "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>", response.body
  end

  test "falls back to placeholder when favicon fetch fails" do
    with_stubbed_favicon_fetch(nil) do
      get "/favicon/sources/Direct%20%2F%20None"
    end

    assert_response :success
    assert_equal "image/svg+xml; charset=utf-8", response.headers["Content-Type"]
    assert_match(/public/, response.headers["Cache-Control"])
    assert_match(/max-age=2592000/, response.headers["Cache-Control"])
    assert_includes response.body, "<svg"
  end

  private
    def with_stubbed_favicon_fetch(result)
      original = Analytics::SourceFavicon.method(:fetch)
      Analytics::SourceFavicon.singleton_class.send(:define_method, :fetch) { |_source| result }
      yield
    ensure
      Analytics::SourceFavicon.singleton_class.send(:define_method, :fetch, original)
    end
end
