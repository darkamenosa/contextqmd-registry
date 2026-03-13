# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class BundlesControllerTest < ActionDispatch::IntegrationTest
      include PageHydrationTestHelper

      fixtures :accounts, :libraries, :versions, :pages, :bundles

      setup do
        @version = versions(:nextjs_stable)
        hydrate_pages(@version)
        @bundle = DocsBundle.refresh!(@version, profile: "full")
      end

      teardown do
        FileUtils.rm_rf(DocsBundle.storage_root)
        Current.reset
      end

      test "show returns a binary bundle download for checksum-addressed URLs" do
        get "/api/v1/libraries/vercel/nextjs/versions/16.1.6/bundles/full?sha256=#{@bundle.sha256}"

        assert_response :ok
        assert_equal "application/octet-stream", response.media_type
        assert_includes response.headers["Content-Disposition"], %(attachment; filename="#{@bundle.filename}")
        assert_includes response.headers["Cache-Control"], "public"
        assert_includes response.headers["Cache-Control"], "immutable"
        assert_equal @bundle.sha256, response.headers["X-Bundle-SHA256"]
        assert_equal File.binread(@bundle.file_path), response.body
      end

      test "show does not mark mutable bundle URLs as immutable" do
        get "/api/v1/libraries/vercel/nextjs/versions/16.1.6/bundles/full"

        assert_response :ok
        assert_includes response.headers["Cache-Control"], "public"
        assert_not_includes response.headers["Cache-Control"], "immutable"
      end

      test "show returns 404 for nonexistent bundle profile" do
        get "/api/v1/libraries/vercel/nextjs/versions/16.1.6/bundles/nonexistent"

        assert_response :not_found

        body = response.parsed_body
        assert_equal "not_found", body["error"]["code"]
      end

      test "show returns conflict when a bundle exists but is not ready" do
        @bundle.update!(status: "pending", sha256: nil, size_bytes: nil)
        FileUtils.rm_f(@bundle.file_path)

        get "/api/v1/libraries/vercel/nextjs/versions/16.1.6/bundles/full"

        assert_response :conflict
        body = response.parsed_body
        assert_equal "not_ready", body.dig("error", "code")
      end

      test "show serves the attached package when the local bundle file is missing" do
        expected_body = File.binread(@bundle.file_path)
        FileUtils.rm_f(@bundle.file_path)

        get "/api/v1/libraries/vercel/nextjs/versions/16.1.6/bundles/full?sha256=#{@bundle.sha256}"

        assert_response :ok
        assert_equal expected_body, response.body
        assert_equal @bundle.sha256, response.headers["X-Bundle-SHA256"]
      end

      test "show returns 404 for private bundles" do
        @bundle.update!(visibility: "private")

        get "/api/v1/libraries/vercel/nextjs/versions/16.1.6/bundles/full"

        assert_response :not_found
        body = response.parsed_body
        assert_equal "not_found", body.dig("error", "code")
      end
    end
  end
end
