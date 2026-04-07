# frozen_string_literal: true

require "test_helper"

class Analytics::GoogleSearchConsole::ClientTest < ActiveSupport::TestCase
  test "refresh_access_token! surfaces error_description when google returns string errors" do
    client = Analytics::GoogleSearchConsole::Client.new
    response = Net::HTTPBadRequest.new("1.1", "400", "Bad Request")
    response.define_singleton_method(:body) do
      {
        error: "invalid_grant",
        error_description: "Token has been expired or revoked."
      }.to_json
    end
    http = build_http(response)
    original_http_start = Net::HTTP.method(:start)

    Net::HTTP.define_singleton_method(:start) do |*_args, **_kwargs, &block|
      block.call(http)
    end

    error = assert_raises(Analytics::GoogleSearchConsole::Client::Error) do
      client.refresh_access_token!("refresh-token")
    end

    assert_equal "Token has been expired or revoked.", error.message
    assert_equal true, error.reauth_required?
  ensure
    Net::HTTP.define_singleton_method(:start, original_http_start)
  end

  private
    def build_http(result)
      Class.new do
        define_method(:initialize) do |result|
          @result = result
        end

        define_method(:request) do |_request|
          @result
        end
      end.new(result)
    end
end
