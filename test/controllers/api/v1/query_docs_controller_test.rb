# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class QueryDocsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @identity, _account, = create_tenant(
          email: "query-test-#{SecureRandom.hex(4)}@example.com",
          name: "Query Test"
        )

        @hex = SecureRandom.hex(4)
        system_account = Account.find_or_create_by!(name: "QueryTest System") { |a| a.personal = false }
        @library = Library.create!(
          account: system_account,
          namespace: "qns-#{@hex}",
          name: "qlib-#{@hex}",
          display_name: "Test Library"
        )
        @version = @library.versions.create!(version: "1.0.0", channel: "stable", generated_at: Time.current)

        @version.pages.create!(
          page_uid: "getting-started",
          path: "getting-started.md",
          title: "Getting Started",
          description: "This guide shows you how to install and configure the library for the first time.",
          bytes: 80,
          headings: [ "Prerequisites", "Installation" ]
        )
        @version.pages.create!(
          page_uid: "api-reference",
          path: "api-reference.md",
          title: "API Reference",
          description: "Complete API reference for all public methods and classes in the library.",
          bytes: 90,
          headings: [ "Methods", "Classes" ]
        )
        @version.pages.create!(
          page_uid: "configuration",
          path: "configuration.md",
          title: "Configuration",
          description: "How to configure database connections, caching, and logging settings.",
          bytes: 70,
          headings: [ "Database", "Caching" ]
        )
      end

      test "returns matching pages for a query" do
        post "/api/v1/libraries/#{@library.namespace}/#{@library.name}/versions/1.0.0/query",
          params: { query: "install configure", max_tokens: 50_000 },
          as: :json

        assert_response :ok

        body = response.parsed_body
        assert body.key?("data")
        assert body.key?("meta")
        assert_operator body["data"].size, :>=, 1
        assert_equal "install configure", body["meta"]["query"]

        first = body["data"].first
        assert first.key?("page_uid")
        assert first.key?("title")
        assert first.key?("content_md")
      end

      test "returns error when query is missing" do
        post "/api/v1/libraries/#{@library.namespace}/#{@library.name}/versions/1.0.0/query",
          params: {},
          as: :json

        assert_response :bad_request

        body = response.parsed_body
        assert_equal "bad_request", body["error"]["code"]
      end

      test "respects max_tokens budget" do
        post "/api/v1/libraries/#{@library.namespace}/#{@library.name}/versions/1.0.0/query",
          params: { query: "library", max_tokens: 500 },
          as: :json

        assert_response :ok

        body = response.parsed_body
        assert_equal 500, body["meta"]["max_tokens"]
      end

      test "returns 404 for nonexistent library" do
        post "/api/v1/libraries/no-such/lib/versions/1.0.0/query",
          params: { query: "test" },
          as: :json

        assert_response :not_found
      end

      test "clamps max_tokens to valid range" do
        post "/api/v1/libraries/#{@library.namespace}/#{@library.name}/versions/1.0.0/query",
          params: { query: "install", max_tokens: 1 },
          as: :json

        assert_response :ok
        assert_equal 500, response.parsed_body["meta"]["max_tokens"]
      end

      test "fast mode returns whole pages without chunk splitting" do
        post "/api/v1/libraries/#{@library.namespace}/#{@library.name}/versions/1.0.0/query",
          params: { query: "install configure", max_tokens: 50_000, mode: "fast" },
          as: :json

        assert_response :ok
        body = response.parsed_body
        assert_equal "fast", body["meta"]["mode"]
        assert_operator body["data"].size, :>=, 1

        first = body["data"].first
        assert first.key?("page_uid")
        assert first.key?("content_md")
      end

      test "full mode is the default" do
        post "/api/v1/libraries/#{@library.namespace}/#{@library.name}/versions/1.0.0/query",
          params: { query: "install", max_tokens: 50_000 },
          as: :json

        assert_response :ok
        assert_equal "full", response.parsed_body["meta"]["mode"]
      end
    end
  end
end
