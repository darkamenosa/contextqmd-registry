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

      test "show with auth returns full manifest" do
        get "/api/v1/libraries/vercel/nextjs/versions/16.1.6/manifest", headers: auth_headers

        assert_response :ok

        body = response.parsed_body
        assert body.key?("data"), "Response should include 'data' key"

        data = body["data"]

        # Library info
        assert_equal "vercel", data["library"]["namespace"]
        assert_equal "nextjs", data["library"]["name"]
        assert_equal "Next.js", data["library"]["display_name"]

        # Version info
        assert_equal "16.1.6", data["version"]["version"]
        assert_equal "stable", data["version"]["channel"]

        # Doc count (pages)
        assert_equal 2, data["doc_count"]

        # Source (from fetch_recipe)
        assert_not_nil data["source"]
        assert_equal "http", data["source"]["source_type"]
        assert_equal "https://nextjs.org/docs", data["source"]["url"]

        # Page index URL
        assert_equal "/api/v1/libraries/vercel/nextjs/versions/16.1.6/page-index", data["page_index_url"]

        # Profiles (from bundles)
        assert_includes data["profiles"], "full"
        assert_includes data["profiles"], "slim"

        # Source policy
        assert_not_nil data["source_policy"]
        assert_equal "MIT", data["source_policy"]["license_name"]
        assert_equal "verified", data["source_policy"]["license_status"]

        # Provenance
        assert_not_nil data["provenance"]
        assert_not_nil data["provenance"]["generated_at"]
        assert_equal "https://nextjs.org/docs", data["provenance"]["source_url"]
      end

      test "show without auth returns 200" do
        get "/api/v1/libraries/vercel/nextjs/versions/16.1.6/manifest"

        assert_response :ok

        body = response.parsed_body
        assert body.key?("data"), "Response should include 'data' key"
        assert_equal "nextjs", body["data"]["library"]["name"]
      end

      test "show returns 404 for nonexistent library or version" do
        get "/api/v1/libraries/vercel/nextjs/versions/99.0.0/manifest", headers: auth_headers

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
