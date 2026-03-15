# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class ManifestsControllerTest < ActionDispatch::IntegrationTest
      include PageHydrationTestHelper

      fixtures :accounts, :libraries, :versions, :pages, :bundles, :fetch_recipes, :source_policies

      setup do
        @version = versions(:nextjs_stable)
        hydrate_pages(@version)
        @full_bundle = DocsBundle.refresh!(@version, profile: "full")
      end

      teardown do
        FileUtils.rm_rf(DocsBundle.storage_root)
        Current.reset
      end

      test "show returns contract-conforming manifest" do
        get "/api/v1/libraries/nextjs/versions/16.1.6/manifest"

        assert_response :ok

        body = response.parsed_body
        assert body.key?("data"), "Response should include 'data' key"

        data = body["data"]

        # Flat top-level fields per API contract
        assert_equal "1.0", data["schema_version"]
        assert_equal "nextjs", data["slug"]
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
        assert_equal "/api/v1/libraries/nextjs/versions/16.1.6/page-index", data["page_index"]["url"]

        # Profiles — hash of profile => { bundle: { format, url, sha256 } }
        assert data["profiles"].is_a?(Hash), "profiles should be a hash"
        assert_equal "tar.gz", data["profiles"]["full"]["bundle"]["format"]
        assert_equal @full_bundle.sha256, data["profiles"]["full"]["bundle"]["sha256"]
        assert_equal "/api/v1/libraries/nextjs/versions/16.1.6/bundles/full?sha256=#{ERB::Util.url_encode(@full_bundle.sha256)}",
          data["profiles"]["full"]["bundle"]["url"]
        assert_not data["profiles"].key?("slim"), "undeliverable ready bundles should not be advertised"

        # Source policy
        assert_not_nil data["source_policy"]
        assert_equal "MIT", data["source_policy"]["license_name"]
        assert_equal "verified", data["source_policy"]["license_status"]

        # Provenance — normalizer_version, splitter_version, manifest_checksum
        assert_not_nil data["provenance"]
        assert data["provenance"].key?("manifest_checksum")
      end

      test "show returns 404 for nonexistent library or version" do
        get "/api/v1/libraries/nextjs/versions/99.0.0/manifest"

        assert_response :not_found

        body = response.parsed_body
        assert_equal "not_found", body["error"]["code"]
      end

      test "GET manifest with 'latest' resolves to default version" do
        get "/api/v1/libraries/nextjs/versions/latest/manifest"

        assert_response :ok

        body = response.parsed_body
        assert_equal "16.1.6", body["data"]["version"]
      end

      test "show resolves manifest by canonical slug when slug differs from legacy name" do
        @version.library.update!(slug: "next")

        get "/api/v1/libraries/next/versions/16.1.6/manifest"

        assert_response :ok
        assert_equal "next", response.parsed_body.dig("data", "slug")
      end

      test "GET manifest with 'stable' resolves to stable channel version" do
        get "/api/v1/libraries/nextjs/versions/stable/manifest"

        assert_response :ok

        body = response.parsed_body
        assert_equal "16.1.6", body["data"]["version"]
        assert_equal "stable", body["data"]["channel"]
      end

      test "show only advertises ready bundles" do
        @version.bundles.create!(profile: "compact", status: "pending")

        get "/api/v1/libraries/nextjs/versions/16.1.6/manifest"

        assert_response :ok

        profiles = response.parsed_body.dig("data", "profiles")
        assert_not profiles.key?("compact")
      end

      test "show does not advertise private bundles" do
        @full_bundle.update!(visibility: "private")

        get "/api/v1/libraries/nextjs/versions/16.1.6/manifest"

        assert_response :ok

        profiles = response.parsed_body.dig("data", "profiles")
        assert_not profiles.key?("full")
      end
    end
  end
end
