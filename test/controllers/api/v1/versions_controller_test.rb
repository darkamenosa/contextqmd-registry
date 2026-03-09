# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class VersionsControllerTest < ActionDispatch::IntegrationTest
      fixtures :accounts, :libraries, :versions

      setup do
        @identity, _account, = create_tenant(
          email: "versions-test-#{SecureRandom.hex(4)}@example.com",
          name: "Versions Test"
        )
        _access_token, @raw_token = AccessToken.generate(
          identity: @identity,
          name: "Test Token",
          permission: :read
        )

        @library = libraries(:nextjs)
      end

      teardown { Current.reset }

      test "index with auth returns versions for a library" do
        get "/api/v1/libraries/vercel/nextjs/versions", headers: auth_headers

        assert_response :ok

        body = response.parsed_body
        assert body.key?("data"), "Response should include 'data' key"
        assert body.key?("meta"), "Response should include 'meta' key"
        assert_kind_of Array, body["data"]
        assert_operator body["data"].size, :>=, 1

        stable = body["data"].find { |v| v["version"] == "16.1.6" }
        assert_not_nil stable, "Should include version 16.1.6"
        assert_equal "stable", stable["channel"]
        assert_equal "sha256:nextjs1616checksum", stable["manifest_checksum"]
        assert_not_nil stable["generated_at"]
      end

      test "index without auth returns 200" do
        get "/api/v1/libraries/vercel/nextjs/versions"

        assert_response :ok

        body = response.parsed_body
        assert body.key?("data"), "Response should include 'data' key"
        assert_kind_of Array, body["data"]
      end

      test "index filters by channel when param provided" do
        get "/api/v1/libraries/vercel/nextjs/versions", params: { channel: "stable" }

        assert_response :ok
        body = response.parsed_body
        channels = body["data"].map { |v| v["channel"] }
        assert channels.all? { |c| c == "stable" }, "All versions should be stable"
      end

      test "index returns all channels when no filter" do
        get "/api/v1/libraries/vercel/nextjs/versions"

        assert_response :ok
        body = response.parsed_body
        assert_operator body["data"].size, :>=, 1
      end

      test "index returns 404 for nonexistent library" do
        get "/api/v1/libraries/unknown/nope/versions", headers: auth_headers

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
