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

      # --- Single endpoint ---

      test "creates crawl request with auto-detected source_type" do
        assert_difference -> { CrawlRequest.count }, 1 do
          post "/api/v1/crawl",
            params: { url: "https://github.com/rails/rails" },
            headers: auth_headers
        end

        assert_response :accepted
        body = response.parsed_body
        assert_equal "github", body["data"]["source_type"]
        assert_equal "pending", body["data"]["status"]
        assert_equal "queued", body["meta"]["status"]
      end

      test "returns error for missing URL" do
        post "/api/v1/crawl",
          params: {},
          headers: auth_headers

        assert_response :bad_request
        body = response.parsed_body
        assert_equal "bad_request", body["error"]["code"]
      end

      test "requires authentication" do
        post "/api/v1/crawl",
          params: { url: "https://github.com/rails/rails" }

        assert_response :unauthorized
      end

      test "rejects read-only token on single create" do
        _read_token, read_raw = AccessToken.generate(
          identity: @identity,
          name: "Read Only",
          permission: :read
        )

        post "/api/v1/crawl",
          params: { url: "https://github.com/rails/rails" },
          headers: { "Authorization" => "Token #{read_raw}" }

        assert_response :unauthorized
      end

      # --- Bulk endpoint ---

      test "bulk creates multiple crawl requests" do
        urls = [
          "https://github.com/rails/rails",
          "https://github.com/facebook/react"
        ]

        assert_difference -> { CrawlRequest.count }, 2 do
          post "/api/v1/crawl/bulk",
            params: { urls: urls },
            headers: auth_headers,
            as: :json
        end

        assert_response :accepted
        body = response.parsed_body
        assert_equal 2, body["meta"]["queued"]
        assert_equal 0, body["meta"]["failed"]
        assert_equal 0, body["meta"]["skipped"]
        assert_equal 2, body["meta"]["total"]
        assert_equal 2, body["data"].size
        assert body["data"].all? { |r| r["status"] == "queued" }
      end

      test "bulk rejects read-only token" do
        _read_token_record, read_raw = AccessToken.generate(
          identity: @identity,
          name: "Read Only",
          permission: :read
        )

        post "/api/v1/crawl/bulk",
          params: { urls: [ "https://github.com/rails/rails" ] },
          headers: { "Authorization" => "Token #{read_raw}" },
          as: :json

        assert_response :unauthorized
      end

      test "bulk enforces max URL limit" do
        urls = 501.times.map { |i| "https://github.com/org/repo-#{i}" }

        post "/api/v1/crawl/bulk",
          params: { urls: urls },
          headers: auth_headers,
          as: :json

        assert_response :unprocessable_entity
        body = response.parsed_body
        assert_equal "too_many_urls", body["error"]["code"]
      end

      test "bulk reports failed URLs inline" do
        urls = [
          "https://github.com/rails/rails",
          "not-a-valid-url"
        ]

        post "/api/v1/crawl/bulk",
          params: { urls: urls },
          headers: auth_headers,
          as: :json

        assert_response :accepted
        body = response.parsed_body
        assert_equal 1, body["meta"]["queued"]
        assert_equal 1, body["meta"]["failed"]
        assert_equal 2, body["meta"]["total"]
      end

      test "bulk reports blank URLs as skipped" do
        urls = [
          "https://github.com/rails/rails",
          "",
          "https://github.com/facebook/react"
        ]

        assert_difference -> { CrawlRequest.count }, 2 do
          post "/api/v1/crawl/bulk",
            params: { urls: urls },
            headers: auth_headers,
            as: :json
        end

        assert_response :accepted
        body = response.parsed_body
        assert_equal 2, body["meta"]["queued"]
        assert_equal 0, body["meta"]["failed"]
        assert_equal 1, body["meta"]["skipped"]
        assert_equal 3, body["meta"]["total"]
        skipped_entries = body["data"].select { |r| r["status"] == "skipped" }
        assert_equal 1, skipped_entries.size
      end

      test "bulk requires authentication" do
        post "/api/v1/crawl/bulk",
          params: { urls: [ "https://github.com/rails/rails" ] },
          as: :json

        assert_response :unauthorized
      end

      private

        def auth_headers
          { "Authorization" => "Token #{@raw_token}" }
        end
    end
  end
end
