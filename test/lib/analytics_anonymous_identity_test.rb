# frozen_string_literal: true

require "test_helper"

class AnalyticsAnonymousIdentityTest < ActiveSupport::TestCase
  test "current token is stable within a rotation window" do
    request = build_request(
      "REMOTE_ADDR" => "173.245.48.5",
      "HTTP_CF_CONNECTING_IP" => "128.101.101.101",
      "HTTP_X_FORWARDED_FOR" => "128.101.101.101",
      "HTTP_USER_AGENT" => "Mozilla/5.0",
      "HTTP_HOST" => "www.contextqmd.com"
    )

    morning = Time.utc(2026, 3, 25, 8, 0, 0)
    evening = Time.utc(2026, 3, 25, 20, 0, 0)

    assert_equal(
      AnalyticsAnonymousIdentity.current(request, now: morning),
      AnalyticsAnonymousIdentity.current(request, now: evening)
    )
  end

  test "rotation changes the current token while keeping the previous token available" do
    request = build_request(
      "REMOTE_ADDR" => "173.245.48.5",
      "HTTP_CF_CONNECTING_IP" => "128.101.101.101",
      "HTTP_X_FORWARDED_FOR" => "128.101.101.101",
      "HTTP_USER_AGENT" => "Mozilla/5.0",
      "HTTP_HOST" => "contextqmd.com"
    )

    before_rotation = Time.utc(2026, 3, 25, 23, 59, 50)
    after_rotation = Time.utc(2026, 3, 26, 0, 0, 10)

    previous_current = AnalyticsAnonymousIdentity.current(request, now: before_rotation)
    rotated_current = AnalyticsAnonymousIdentity.current(request, now: after_rotation)

    refute_equal previous_current, rotated_current
    assert_equal previous_current, AnalyticsAnonymousIdentity.previous(request, now: after_rotation)
    assert_equal [ rotated_current, previous_current ], AnalyticsAnonymousIdentity.tokens(request, now: after_rotation)
  end

  private
    def build_request(env)
      ActionDispatch::Request.new(
        {
          "rack.url_scheme" => "https",
          "REQUEST_METHOD" => "GET",
          "PATH_INFO" => "/"
        }.merge(env)
      )
    end
end
