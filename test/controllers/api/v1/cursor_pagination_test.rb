# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class CursorPaginationTest < ActionDispatch::IntegrationTest
      fixtures :accounts, :libraries, :versions, :pages

      setup do
        @identity, @account, = create_tenant(
          email: "pagination-test-#{SecureRandom.hex(4)}@example.com",
          name: "Pagination Test"
        )
        _access_token, @raw_token = AccessToken.generate(
          identity: @identity,
          name: "Test Token",
          permission: :read
        )
      end

      teardown { Current.reset }

      # -- Libraries pagination --

      test "libraries index returns null cursor when all results fit in one page" do
        get api_v1_libraries_path

        assert_response :ok

        body = response.parsed_body
        assert_nil body["meta"]["cursor"], "Cursor should be nil when all results fit"
        assert_operator body["data"].size, :>=, 2
      end

      test "libraries index paginates with per_page=1 via cursor" do
        get api_v1_libraries_path, params: { per_page: 1 }

        assert_response :ok

        body = response.parsed_body
        assert_equal 1, body["data"].size, "Should return exactly 1 library"
        assert_not_nil body["meta"]["cursor"], "Cursor should be present when more pages exist"

        first_lib = body["data"].first

        # Fetch next page using cursor
        get api_v1_libraries_path, params: { cursor: body["meta"]["cursor"], per_page: 1 }

        assert_response :ok

        body2 = response.parsed_body
        assert_equal 1, body2["data"].size, "Second page should return 1 library"
        assert_not_equal first_lib["slug"], body2["data"].first["slug"], "Should return a different library"
      end

      test "libraries index cursor walks through all records" do
        all_slugs = []
        cursor = nil

        3.times do
          params = { per_page: 1 }
          params[:cursor] = cursor if cursor

          get api_v1_libraries_path, params: params

          assert_response :ok

          body = response.parsed_body
          all_slugs.concat(body["data"].map { |l| l["slug"] })
          cursor = body["meta"]["cursor"]

          break if cursor.nil?
        end

        assert_nil cursor, "Cursor should be nil after exhausting all pages"
        assert_includes all_slugs, "nextjs"
        assert_includes all_slugs, "rails"
      end

      test "libraries index with invalid cursor returns results from beginning" do
        get api_v1_libraries_path, params: { cursor: "!!!invalid!!!" }

        assert_response :ok

        body = response.parsed_body
        assert_kind_of Array, body["data"]
      end

      # -- Versions pagination --

      test "versions index returns null cursor when all results fit in one page" do
        get "/api/v1/libraries/nextjs/versions"

        assert_response :ok

        body = response.parsed_body
        assert_nil body["meta"]["cursor"]
        assert_operator body["data"].size, :>=, 1
      end

      test "versions index paginates with per_page=1 via cursor" do
        get "/api/v1/libraries/nextjs/versions", params: { per_page: 1 }

        assert_response :ok

        body = response.parsed_body
        assert_equal 1, body["data"].size

        # nextjs has 2 versions (stable + canary), so there should be a next page
        assert_not_nil body["meta"]["cursor"], "Should have next cursor with 2 versions and per_page=1"

        first_version = body["data"].first["version"]

        get "/api/v1/libraries/nextjs/versions", params: { cursor: body["meta"]["cursor"], per_page: 1 }

        assert_response :ok

        body2 = response.parsed_body
        assert_equal 1, body2["data"].size
        assert_not_equal first_version, body2["data"].first["version"]
        assert_nil body2["meta"]["cursor"], "Should be no more pages"
      end

      # -- Page index pagination --

      test "page index returns null cursor when all results fit in one page" do
        get "/api/v1/libraries/nextjs/versions/16.1.6/page-index"

        assert_response :ok

        body = response.parsed_body
        assert_nil body["meta"]["cursor"]
        assert_equal 2, body["data"].size
      end

      test "page index paginates with per_page=1 via cursor" do
        get "/api/v1/libraries/nextjs/versions/16.1.6/page-index", params: { per_page: 1 }

        assert_response :ok

        body = response.parsed_body
        assert_equal 1, body["data"].size
        assert_not_nil body["meta"]["cursor"], "Should have next cursor with 2 pages and per_page=1"

        first_uid = body["data"].first["page_uid"]

        get "/api/v1/libraries/nextjs/versions/16.1.6/page-index",
          params: { cursor: body["meta"]["cursor"], per_page: 1 }

        assert_response :ok

        body2 = response.parsed_body
        assert_equal 1, body2["data"].size
        assert_not_equal first_uid, body2["data"].first["page_uid"]
        assert_nil body2["meta"]["cursor"], "Should be no more pages"
      end

      private

        def auth_headers
          { "Authorization" => "Bearer #{@raw_token}" }
        end
    end
  end
end
