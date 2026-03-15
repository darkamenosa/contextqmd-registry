# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class ResolveControllerTest < ActionDispatch::IntegrationTest
      setup do
        @identity, @account, = create_tenant(
          email: "api-resolve-#{SecureRandom.hex(4)}@example.com",
          name: "API Resolve"
        )
        _access_token, @raw_token = AccessToken.generate(
          identity: @identity,
          name: "Resolve Token",
          permission: :write
        )

        @hex = SecureRandom.hex(4)
        @nextjs = Library.create!(
          account: @account,
          namespace: "vercel-#{@hex}",
          name: "nextjs-#{@hex}",
          slug: "nextjs-#{@hex}",
          display_name: "Next.js",
          aliases: [ "nextalias-#{@hex}", "nextdot-#{@hex}" ],
          homepage_url: "https://nextjs.org",
          default_version: "16.1.6"
        )
        @nextjs_stable = Version.create!(
          library: @nextjs,
          version: "16.1.6",
          channel: "stable",
          generated_at: 2.days.ago,
          source_url: "https://nextjs.org/docs",
          manifest_checksum: "sha256:nextjs1616checksum"
        )
        @nextjs_canary = Version.create!(
          library: @nextjs,
          version: "17.0.0-canary.1",
          channel: "canary",
          generated_at: 1.day.ago,
          source_url: "https://nextjs.org/docs"
        )
      end

      teardown { Current.reset }

      # -- Authentication --

      test "POST /resolve without auth returns 200" do
        post api_v1_resolve_path, params: { query: @nextjs.slug }, as: :json

        assert_response :ok

        body = response.parsed_body
        assert body.key?("data"), "Response should include 'data' key"
        assert_equal "nextjs-#{@hex}", body["data"]["library"]["slug"]
      end

      # -- Validation --

      test "POST /resolve without query returns 400" do
        post api_v1_resolve_path,
          params: {},
          headers: auth_headers,
          as: :json

        assert_response :bad_request

        body = response.parsed_body
        assert_equal "bad_request", body["error"]["code"]
        assert_match(/query/i, body["error"]["message"])
      end

      # -- Canonical slug match --

      test "POST /resolve with canonical slug returns library and version" do
        post api_v1_resolve_path,
          params: { query: @nextjs.slug },
          headers: auth_headers,
          as: :json

        assert_response :ok

        body = response.parsed_body
        assert body.key?("data"), "Response should include 'data' key"

        library = body["data"]["library"]
        assert_equal "nextjs-#{@hex}", library["slug"]
        assert_equal "Next.js", library["display_name"]
        assert_equal "16.1.6", library["default_version"]

        version = body["data"]["version"]
        assert_equal "16.1.6", version["version"]
        assert_equal "stable", version["channel"]
        assert_equal "sha256:nextjs1616checksum", version["manifest_checksum"]

        assert body["data"].key?("manifest_url")
        assert_includes body["data"]["manifest_url"], @nextjs_stable.version
      end

      test "POST /resolve returns manifest url keyed by slug" do
        post api_v1_resolve_path,
          params: { query: @nextjs.slug },
          headers: auth_headers,
          as: :json

        assert_response :ok

        body = response.parsed_body
        assert_equal "/api/v1/libraries/#{@nextjs.slug}/versions/16.1.6/manifest", body["data"]["manifest_url"]
      end

      # -- Alias match --

      test "POST /resolve with alias returns library and version" do
        post api_v1_resolve_path,
          params: { query: "nextalias-#{@hex}" },
          headers: auth_headers,
          as: :json

        assert_response :ok

        body = response.parsed_body
        library = body["data"]["library"]
        assert_equal "nextjs-#{@hex}", library["slug"]
      end

      # -- Version hint: stable --

      test "POST /resolve with version_hint stable returns stable version" do
        post api_v1_resolve_path,
          params: { query: @nextjs.slug, version_hint: "stable" },
          headers: auth_headers,
          as: :json

        assert_response :ok

        body = response.parsed_body
        version = body["data"]["version"]
        assert_equal "16.1.6", version["version"]
        assert_equal "stable", version["channel"]
      end

      # -- Version hint: exact --

      test "POST /resolve with exact version_hint returns that version" do
        post api_v1_resolve_path,
          params: { query: @nextjs.slug, version_hint: "17.0.0-canary.1" },
          headers: auth_headers,
          as: :json

        assert_response :ok

        body = response.parsed_body
        version = body["data"]["version"]
        assert_equal "17.0.0-canary.1", version["version"]
        assert_equal "canary", version["channel"]
      end

      # -- Version hint: canary channel --

      test "POST /resolve with version_hint canary returns canary version" do
        post api_v1_resolve_path,
          params: { query: @nextjs.slug, version_hint: "canary" },
          headers: auth_headers,
          as: :json

        assert_response :ok

        body = response.parsed_body
        version = body["data"]["version"]
        assert_equal "17.0.0-canary.1", version["version"]
        assert_equal "canary", version["channel"]
      end

      # -- Not found --

      test "POST /resolve with unknown query returns 404" do
        post api_v1_resolve_path,
          params: { query: "nonexistent-library-#{@hex}" },
          headers: auth_headers,
          as: :json

        assert_response :not_found

        body = response.parsed_body
        assert_equal "not_found", body["error"]["code"]
      end

      test "POST /resolve with known library but unknown version returns 404" do
        post api_v1_resolve_path,
          params: { query: @nextjs.slug, version_hint: "99.0.0" },
          headers: auth_headers,
          as: :json

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
