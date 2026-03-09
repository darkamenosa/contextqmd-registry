# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class PageIndexControllerTest < ActionDispatch::IntegrationTest
      fixtures :accounts, :libraries, :versions, :pages

      setup do
        @identity, _account, = create_tenant(
          email: "pages-test-#{SecureRandom.hex(4)}@example.com",
          name: "Pages Test"
        )
        _access_token, @raw_token = AccessToken.generate(
          identity: @identity,
          name: "Test Token",
          permission: :read
        )
      end

      teardown { Current.reset }

      # -- index (page-index) --

      test "index with auth returns paginated page listing" do
        get "/api/v1/libraries/vercel/nextjs/versions/16.1.6/page-index", headers: auth_headers

        assert_response :ok

        body = response.parsed_body
        assert body.key?("data"), "Response should include 'data' key"
        assert body.key?("meta"), "Response should include 'meta' key"
        assert_kind_of Array, body["data"]
        assert_equal 2, body["data"].size

        page = body["data"].find { |p| p["page_uid"] == "pg_install_001" }
        assert_not_nil page, "Should include installation page"
        assert_equal "app/getting-started/installation.md", page["path"]
        assert_equal "Installation", page["title"]
        assert_equal "https://nextjs.org/docs/app/getting-started/installation", page["url"]
        assert_equal "sha256:install_page_checksum", page["checksum"]
        assert_equal 9123, page["bytes"]
        assert_includes page["headings"], "Installation"
        assert_not_nil page["updated_at"]
      end

      test "index without auth returns 401" do
        get "/api/v1/libraries/vercel/nextjs/versions/16.1.6/page-index"

        assert_response :unauthorized
      end

      test "index returns 404 for nonexistent version" do
        get "/api/v1/libraries/vercel/nextjs/versions/99.0.0/page-index", headers: auth_headers

        assert_response :not_found

        body = response.parsed_body
        assert_equal "not_found", body["error"]["code"]
      end

      # -- show (single page) --

      test "show with auth returns single page content" do
        get "/api/v1/libraries/vercel/nextjs/versions/16.1.6/pages/pg_install_001", headers: auth_headers

        assert_response :ok

        body = response.parsed_body
        assert body.key?("data"), "Response should include 'data' key"

        data = body["data"]
        assert_equal "pg_install_001", data["page_uid"]
        assert_equal "app/getting-started/installation.md", data["path"]
        assert_equal "Installation", data["title"]
        assert_equal "https://nextjs.org/docs/app/getting-started/installation", data["url"]
        assert data.key?("content_md"), "Response should include content_md"
      end

      test "show without auth returns 401" do
        get "/api/v1/libraries/vercel/nextjs/versions/16.1.6/pages/pg_install_001"

        assert_response :unauthorized
      end

      test "show returns 404 for nonexistent page" do
        get "/api/v1/libraries/vercel/nextjs/versions/16.1.6/pages/pg_nonexistent", headers: auth_headers

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
