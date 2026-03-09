# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class BundlesControllerTest < ActionDispatch::IntegrationTest
      fixtures :accounts, :libraries, :versions, :bundles

      setup do
        @identity, _account, = create_tenant(
          email: "bundles-test-#{SecureRandom.hex(4)}@example.com",
          name: "Bundles Test"
        )
        _access_token, @raw_token = AccessToken.generate(
          identity: @identity,
          name: "Test Token",
          permission: :read
        )
      end

      teardown { Current.reset }

      test "show with auth returns bundle metadata" do
        get "/api/v1/libraries/vercel/nextjs/versions/16.1.6/bundles/slim", headers: auth_headers

        assert_response :ok

        body = response.parsed_body
        assert body.key?("data"), "Response should include 'data' key"

        data = body["data"]
        assert_equal "slim", data["profile"]
        assert_equal "tar.zst", data["format"]
        assert_equal "sha256:nextjs_slim_bundle_hash", data["sha256"]
        assert_equal 1_048_576, data["size_bytes"]
        assert_equal "https://cdn.example.com/bundles/nextjs-16.1.6-slim.tar.zst", data["url"]
      end

      test "show without auth returns 200" do
        get "/api/v1/libraries/vercel/nextjs/versions/16.1.6/bundles/slim"

        assert_response :ok

        body = response.parsed_body
        assert body.key?("data"), "Response should include 'data' key"
        assert_equal "slim", body["data"]["profile"]
      end

      test "show returns 404 for nonexistent bundle profile" do
        get "/api/v1/libraries/vercel/nextjs/versions/16.1.6/bundles/nonexistent", headers: auth_headers

        assert_response :not_found

        body = response.parsed_body
        assert_equal "not_found", body["error"]["code"]
      end

      private

        def auth_headers
          { "Authorization" => "Bearer #{@raw_token}" }
        end
    end
  end
end
