# frozen_string_literal: true

require "test_helper"

class DocsFetcher::OpenapiTest < ActiveSupport::TestCase
  setup do
    @fetcher = DocsFetcher::Openapi.new
  end

  SAMPLE_SPEC = {
    "openapi" => "3.0.0",
    "info" => {
      "title" => "Pet Store API",
      "version" => "1.0.0",
      "description" => "A sample API for pets"
    },
    "servers" => [
      { "url" => "https://api.example.com", "description" => "Production" }
    ],
    "paths" => {
      "/pets" => {
        "get" => {
          "summary" => "List all pets",
          "tags" => [ "Pets" ],
          "parameters" => [
            { "name" => "limit", "in" => "query", "schema" => { "type" => "integer" }, "description" => "Max results" }
          ],
          "responses" => {
            "200" => { "description" => "A list of pets" }
          }
        },
        "post" => {
          "summary" => "Create a pet",
          "tags" => [ "Pets" ],
          "requestBody" => {
            "description" => "Pet to create",
            "content" => {
              "application/json" => { "schema" => { "$ref" => "#/components/schemas/Pet" } }
            }
          },
          "responses" => {
            "201" => { "description" => "Created" }
          }
        }
      },
      "/pets/{id}" => {
        "get" => {
          "summary" => "Get a pet by ID",
          "tags" => [ "Pets" ],
          "parameters" => [
            { "name" => "id", "in" => "path", "required" => true, "schema" => { "type" => "string" } }
          ],
          "responses" => {
            "200" => { "description" => "A pet" },
            "404" => { "description" => "Not found" }
          }
        }
      }
    },
    "components" => {
      "schemas" => {
        "Pet" => {
          "type" => "object",
          "description" => "A pet in the store",
          "required" => [ "name" ],
          "properties" => {
            "id" => { "type" => "integer", "description" => "Pet ID" },
            "name" => { "type" => "string", "description" => "Pet name" },
            "status" => { "type" => "string", "description" => "Pet status" }
          }
        }
      }
    }
  }.freeze

  test "fetch returns a Result with overview, endpoint, and schema pages" do
    fetcher = DocsFetcher::Openapi.new
    fetcher.define_singleton_method(:http_get) { |*_args, **_kw| SAMPLE_SPEC.to_json }

    result = fetcher.fetch("https://api.example.com/openapi.json")

    assert_instance_of DocsFetcher::Result, result
    assert_equal "api", result.namespace
    assert_equal "pet-store-api", result.name
    assert_equal "Pet Store API", result.display_name
    assert_equal "1.0.0", result.version

    page_uids = result.pages.map { |p| p[:page_uid] }
    assert_includes page_uids, "overview"
    assert_includes page_uids, "pets"
    assert_includes page_uids, "schemas"
  end

  test "overview page includes title, description, and servers" do
    spec = SAMPLE_SPEC
    page = @fetcher.send(:overview_page, spec, "https://example.com/api")

    assert_equal "overview", page[:page_uid]
    assert_includes page[:content], "Pet Store API"
    assert_includes page[:content], "A sample API for pets"
    assert_includes page[:content], "https://api.example.com"
  end

  test "endpoint pages group by tag" do
    spec = SAMPLE_SPEC
    pages = @fetcher.send(:endpoint_pages, spec, "https://example.com/api")

    assert_equal 1, pages.size
    pets_page = pages.first
    assert_equal "Pets", pets_page[:title]
    assert_includes pets_page[:content], "GET /pets"
    assert_includes pets_page[:content], "POST /pets"
    assert_includes pets_page[:content], "GET /pets/{id}"
  end

  test "schema pages render component schemas as markdown table" do
    spec = SAMPLE_SPEC
    pages = @fetcher.send(:schema_pages, spec, "https://example.com/api")

    assert_equal 1, pages.size
    schema_page = pages.first
    assert_equal "schemas", schema_page[:page_uid]
    assert_includes schema_page[:content], "Pet"
    assert_includes schema_page[:content], "`name`"
    assert_includes schema_page[:content], "Yes"  # required field
  end

  test "parse_spec handles JSON" do
    parsed = @fetcher.send(:parse_spec, SAMPLE_SPEC.to_json)
    assert_equal "3.0.0", parsed["openapi"]
  end

  test "parse_spec handles YAML" do
    yaml_spec = "openapi: '3.0.0'\ninfo:\n  title: Test API\n  version: '1.0.0'\npaths: {}\n"
    parsed = @fetcher.send(:parse_spec, yaml_spec)
    assert_equal "3.0.0", parsed["openapi"]
    assert_equal "Test API", parsed.dig("info", "title")
  end

  test "fetch rejects non-Hash parse results as invalid specs" do
    fetcher = DocsFetcher::Openapi.new
    fetcher.define_singleton_method(:http_get) { |*_args, **_kw| "just a plain string" }

    # parse_spec returns a String (YAML parses anything), but fetch checks is_a?(Hash)
    assert_raises(RuntimeError, /Invalid OpenAPI spec/) { fetcher.fetch("https://example.com/api.json") }
  end

  test "extract_metadata derives namespace from host" do
    spec = { "info" => { "title" => "My API", "version" => "2.0" } }
    uri = URI.parse("https://api.example.com/spec.json")
    metadata = @fetcher.send(:extract_metadata, spec, uri)

    assert_equal "api", metadata[:namespace]
    assert_equal "my-api", metadata[:name]
    assert_equal "My API", metadata[:display_name]
    assert_equal "2.0", metadata[:version]
  end

  test "fetch raises when HTTP returns nil" do
    fetcher = DocsFetcher::Openapi.new
    fetcher.define_singleton_method(:http_get) { |*_args, **_kw| nil }

    assert_raises(RuntimeError) { fetcher.fetch("https://example.com/api.json") }
  end

  test "fetch raises when spec is invalid" do
    fetcher = DocsFetcher::Openapi.new
    fetcher.define_singleton_method(:http_get) { |*_args, **_kw| "not a valid spec" }

    assert_raises(RuntimeError) { fetcher.fetch("https://example.com/api.json") }
  end

  test "slugify handles special characters" do
    assert_equal "hello-world", @fetcher.send(:slugify, "Hello World!")
    assert_equal "api-v20", @fetcher.send(:slugify, "API v2.0")
    assert_equal "api", @fetcher.send(:slugify, "")
  end
end
