# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class ManifestsControllerTest < ActionDispatch::IntegrationTest
      fixtures :accounts, :libraries, :versions, :pages, :bundles, :fetch_recipes, :source_policies

      setup do
        @identity, _account, = create_tenant(
          email: "manifests-test-#{SecureRandom.hex(4)}@example.com",
          name: "Manifests Test"
        )
        _access_token, @raw_token = AccessToken.generate(
          identity: @identity,
          name: "Test Token",
          permission: :read
        )
      end

      teardown { Current.reset }

      test "show with auth returns contract-conforming manifest" do
        get "/api/v1/libraries/vercel/nextjs/versions/16.1.6/manifest", headers: auth_headers

        assert_response :ok

        body = response.parsed_body
        assert body.key?("data"), "Response should include 'data' key"

        data = body["data"]

        # Flat top-level fields per API contract
        assert_equal "1.0", data["schema_version"]
        assert_equal "vercel", data["namespace"]
        assert_equal "nextjs", data["name"]
        assert_equal "Next.js", data["display_name"]
        assert_equal "16.1.6", data["version"]
        assert_equal "stable", data["channel"]
        assert_not_nil data["generated_at"]

        # Doc count
        assert_equal 2, data["doc_count"]

        # Source (from fetch_recipe) — uses "type" not "source_type"
        assert_not_nil data["source"]
        assert_equal "http", data["source"]["type"]
        assert_equal "https://nextjs.org/docs", data["source"]["url"]

        # Page index — object with url, not flat string
        assert_not_nil data["page_index"]
        assert_equal "/api/v1/libraries/vercel/nextjs/versions/16.1.6/page-index", data["page_index"]["url"]

        # Profiles — hash of profile => { bundle: { format, url, sha256 } }
        assert data["profiles"].is_a?(Hash), "profiles should be a hash"
        assert data["profiles"].key?("slim") || data["profiles"].key?("full"),
          "profiles should include slim or full"

        # Source policy
        assert_not_nil data["source_policy"]
        assert_equal "MIT", data["source_policy"]["license_name"]
        assert_equal "verified", data["source_policy"]["license_status"]

        # Provenance — normalizer_version, splitter_version, manifest_checksum
        assert_not_nil data["provenance"]
        assert data["provenance"].key?("manifest_checksum")
      end

      test "show without auth returns 200" do
        get "/api/v1/libraries/vercel/nextjs/versions/16.1.6/manifest"

        assert_response :ok

        body = response.parsed_body
        assert body.key?("data"), "Response should include 'data' key"
        assert_equal "nextjs", body["data"]["name"]
      end

      test "show returns 404 for nonexistent library or version" do
        get "/api/v1/libraries/vercel/nextjs/versions/99.0.0/manifest", headers: auth_headers

        assert_response :not_found

        body = response.parsed_body
        assert_equal "not_found", body["error"]["code"]
      end

      test "GET manifest with 'latest' resolves to default version" do
        get "/api/v1/libraries/vercel/nextjs/versions/latest/manifest"

        assert_response :ok

        body = response.parsed_body
        assert_equal "16.1.6", body["data"]["version"]
      end

      test "GET manifest with 'stable' resolves to stable channel version" do
        get "/api/v1/libraries/vercel/nextjs/versions/stable/manifest"

        assert_response :ok

        body = response.parsed_body
        assert_equal "16.1.6", body["data"]["version"]
        assert_equal "stable", body["data"]["channel"]
      end

      private

        def auth_headers
          { "Authorization" => "Bearer #{@raw_token}" }
        end
    end
  end
end
