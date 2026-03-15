# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class LibrariesControllerTest < ActionDispatch::IntegrationTest
      fixtures :accounts, :libraries, :versions, :pages, :source_policies

      setup do
        @identity, @account, = create_tenant(
          email: "lib-test-#{SecureRandom.hex(4)}@example.com",
          name: "Library Test"
        )
        _access_token, @raw_token = AccessToken.generate(
          identity: @identity,
          name: "Test Token",
          permission: :read
        )

        # Use fixture libraries (vercel/nextjs and rails/rails from libraries.yml)
        @nextjs = libraries(:nextjs)
        @rails_lib = libraries(:rails)
      end

      teardown { Current.reset }

      # -- GET /api/v1/libraries (index) --

      test "index without auth returns 200" do
        get api_v1_libraries_path

        assert_response :ok

        body = response.parsed_body
        assert body.key?("data"), "Response should include 'data' key"
        assert_kind_of Array, body["data"]
      end

      test "index with auth returns 200 with array of libraries" do
        get api_v1_libraries_path, headers: auth_headers

        assert_response :ok

        body = response.parsed_body
        assert body.key?("data"), "Response should include 'data' key"
        assert body.key?("meta"), "Response should include 'meta' key"
        assert_kind_of Array, body["data"]
        assert_operator body["data"].size, :>=, 2

        lib = body["data"].find { |l| l["slug"] == "nextjs" }
        assert_not_nil lib, "Should include nextjs library"
        assert_equal "nextjs", lib["slug"]
        assert_equal "Next.js", lib["display_name"]
        assert_includes lib["aliases"], "next"
        assert_includes lib["aliases"], "next.js"
        assert_equal "https://nextjs.org", lib["homepage_url"]
        assert_equal "16.1.6", lib["default_version"]
        assert lib.key?("source_type"), "Should include source_type field"
        assert_equal "verified", lib["license_status"]
      end

      test "index with query filters results by name" do
        get api_v1_libraries_path, params: { query: "next" }, headers: auth_headers

        assert_response :ok

        body = response.parsed_body
        slugs = body["data"].map { |l| l["slug"] }
        assert_includes slugs, "nextjs"
        refute_includes slugs, "rails"
      end

      test "index with query filters results by alias" do
        get api_v1_libraries_path, params: { query: "ror" }, headers: auth_headers

        assert_response :ok

        body = response.parsed_body
        slugs = body["data"].map { |l| l["slug"] }
        assert_includes slugs, "rails"
        refute_includes slugs, "nextjs"
      end

      test "index returns cursor in meta" do
        get api_v1_libraries_path, headers: auth_headers

        assert_response :ok

        body = response.parsed_body
        assert body["meta"].key?("cursor"), "Meta should include cursor key"
      end

      test "index with query preserves ranked order and disables cursor pagination" do
        get api_v1_libraries_path, params: { query: "rails" }, headers: auth_headers

        assert_response :ok

        body = response.parsed_body
        assert_equal [ "rails" ], body["data"].map { |lib| lib["slug"] }
        assert_nil body["meta"]["cursor"]
      end

      # -- GET /api/v1/libraries/:slug (show) --

      test "show without auth returns 200" do
        get "/api/v1/libraries/nextjs"

        assert_response :ok

        body = response.parsed_body
        assert body.key?("data"), "Response should include 'data' key"
        assert_equal "nextjs", body["data"]["slug"]
      end

      test "show with auth returns 200 with single library" do
        get "/api/v1/libraries/nextjs",
          headers: auth_headers

        assert_response :ok

        body = response.parsed_body
        assert body.key?("data"), "Response should include 'data' key"
        assert body.key?("meta"), "Response should include 'meta' key"

        lib = body["data"]
        assert_equal "nextjs", lib["slug"]
        assert_equal "Next.js", lib["display_name"]
        assert_includes lib["aliases"], "next"
        assert_equal "https://nextjs.org", lib["homepage_url"]
        assert_equal "16.1.6", lib["default_version"]
        assert lib.key?("source_type"), "Should include source_type field"
        assert_equal "verified", lib["license_status"]
      end

      test "show resolves by canonical slug when slug differs from legacy name" do
        @nextjs.update!(slug: "next")

        get "/api/v1/libraries/next", headers: auth_headers

        assert_response :ok
        assert_equal "next", response.parsed_body.dig("data", "slug")
        assert_equal "Next.js", response.parsed_body.dig("data", "display_name")
      end

      test "show includes stats for library with versions" do
        get "/api/v1/libraries/nextjs"

        assert_response :ok
        lib = response.parsed_body["data"]
        assert lib.key?("version_count"), "Should include version_count"
        assert lib.key?("stats"), "Detail view should include stats"
      end

      test "index does not include stats" do
        get api_v1_libraries_path

        assert_response :ok
        lib = response.parsed_body["data"].first
        assert_not lib.key?("stats"), "Index view should not include stats"
      end

      test "show returns 404 for nonexistent library" do
        get "/api/v1/libraries/nope",
          headers: auth_headers

        assert_response :not_found

        body = response.parsed_body
        assert body.key?("error"), "Response should include 'error' key"
        assert_equal "not_found", body["error"]["code"]
      end

      private

        def auth_headers
          { "Authorization" => "Bearer #{@raw_token}" }
        end
    end
  end
end
