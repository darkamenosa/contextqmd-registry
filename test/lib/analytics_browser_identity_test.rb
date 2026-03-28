# frozen_string_literal: true

require "test_helper"

class AnalyticsBrowserIdentityTest < ActiveSupport::TestCase
  test "current prefers the request-scoped browser id" do
    request = build_request
    request.set_header(AnalyticsBrowserIdentity::REQUEST_ENV_KEY, "request-browser-id")

    assert_equal "request-browser-id", AnalyticsBrowserIdentity.current(request)
  end

  test "current falls back to the browser id cookie" do
    request = build_request(
      "HTTP_COOKIE" => "#{AnalyticsBrowserIdentity::COOKIE_NAME}=cookie-browser-id"
    )

    assert_equal "cookie-browser-id", AnalyticsBrowserIdentity.current(request)
    assert_equal "cookie-browser-id", request.get_header(AnalyticsBrowserIdentity::REQUEST_ENV_KEY)
  end

  test "ensure returns the existing browser id without rewriting cookies" do
    request = build_request
    request.set_header(AnalyticsBrowserIdentity::REQUEST_ENV_KEY, "request-browser-id")
    cookies = {}

    browser_id = AnalyticsBrowserIdentity.ensure!(request, cookies:)

    assert_equal "request-browser-id", browser_id
    assert_empty cookies
  end

  test "ensure generates and stores a browser id when one is missing" do
    request = build_request
    cookies = {}

    browser_id = AnalyticsBrowserIdentity.ensure!(request, cookies:)

    assert_equal browser_id, request.get_header(AnalyticsBrowserIdentity::REQUEST_ENV_KEY)
    assert_equal browser_id, cookies.dig(AnalyticsBrowserIdentity::COOKIE_NAME, :value)
    assert_equal true, cookies.dig(AnalyticsBrowserIdentity::COOKIE_NAME, :httponly)
    assert_equal :lax, cookies.dig(AnalyticsBrowserIdentity::COOKIE_NAME, :same_site)
  end

  private
    def build_request(env = {})
      ActionDispatch::Request.new(
        {
          "rack.url_scheme" => "https",
          "REQUEST_METHOD" => "GET",
          "PATH_INFO" => "/"
        }.merge(env)
      )
    end
end
