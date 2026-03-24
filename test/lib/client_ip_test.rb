# frozen_string_literal: true

require "test_helper"

class ClientIpTest < ActiveSupport::TestCase
  test "public prefers cf-connecting-ip when request comes from a trusted cloudflare proxy" do
    request = build_request(
      "REMOTE_ADDR" => "173.245.48.5",
      "HTTP_CF_CONNECTING_IP" => "128.101.101.101",
      "HTTP_X_FORWARDED_FOR" => "128.101.101.101"
    )

    assert_equal "128.101.101.101", ClientIp.public(request)
  end

  test "public ignores spoofed cloudflare headers from untrusted sources" do
    request = build_request(
      "REMOTE_ADDR" => "8.8.8.8",
      "HTTP_CF_CONNECTING_IP" => "128.101.101.101",
      "HTTP_X_FORWARDED_FOR" => "128.101.101.101"
    )

    assert_equal "8.8.8.8", ClientIp.public(request)
  end

  test "best_effort keeps private addresses for non-public local requests" do
    request = build_request("REMOTE_ADDR" => "10.0.0.1")

    assert_equal "10.0.0.1", ClientIp.best_effort(request)
  end

  private
    def build_request(env)
      ActionDispatch::Request.new(
        {
          "rack.url_scheme" => "http",
          "REQUEST_METHOD" => "GET",
          "HTTP_HOST" => "localhost",
          "PATH_INFO" => "/"
        }.merge(env)
      )
    end
end
