# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class CrawlRequestsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @identity, _account, _user = create_tenant(
          email: "crawl-test-#{SecureRandom.hex(4)}@example.com",
          name: "Crawl Tester"
        )
        _access_token, @raw_token = AccessToken.generate(
          identity: @identity,
          name: "Crawl Token",
          permission: :write
        )
      end

      teardown do
        Current.reset
      end

      test "creates crawl request with auto-detected source_type" do
        assert_difference -> { CrawlRequest.count }, 1 do
          post "/api/v1/crawl",
            params: { url: "https://github.com/rails/rails" },
            headers: auth_headers
        end

        assert_response :ok
        body = response.parsed_body
        assert_equal "git", body["data"]["source_type"]
        assert_equal "pending", body["data"]["status"]
        assert_equal "queued", body["meta"]["status"]
      end

      test "returns validation error for missing URL" do
        post "/api/v1/crawl",
          params: {},
          headers: auth_headers

        assert_response :unprocessable_entity
        body = response.parsed_body
        assert_equal "validation_error", body["error"]["code"]
      end

      test "requires authentication" do
        post "/api/v1/crawl",
          params: { url: "https://github.com/rails/rails" }

        assert_response :unauthorized
      end

      private

        def auth_headers
          { "Authorization" => "Token #{@raw_token}" }
        end
    end
  end
end
