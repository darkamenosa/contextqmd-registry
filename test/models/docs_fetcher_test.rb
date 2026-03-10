# frozen_string_literal: true

require "test_helper"

class DocsFetcherTest < ActiveSupport::TestCase
  # --- detect_source_type ---

  test "detects github.com as github" do
    assert_equal "github", DocsFetcher.detect_source_type("https://github.com/rails/rails")
  end

  test "detects github.com with branch as github" do
    assert_equal "github", DocsFetcher.detect_source_type("https://github.com/vercel/next.js/tree/canary")
  end

  test "detects gitlab.com as gitlab" do
    assert_equal "gitlab", DocsFetcher.detect_source_type("https://gitlab.com/group/project")
  end

  test "detects self-hosted gitlab as gitlab" do
    assert_equal "gitlab", DocsFetcher.detect_source_type("https://gitlab.mycompany.com/team/repo")
  end

  test "detects llms.txt as llms_txt" do
    assert_equal "llms_txt", DocsFetcher.detect_source_type("https://react.dev/llms.txt")
  end

  test "detects llms-full.txt as llms_txt" do
    assert_equal "llms_txt", DocsFetcher.detect_source_type("https://nextjs.org/docs/llms-full.txt")
  end

  test "detects llms-small.txt as llms_txt" do
    assert_equal "llms_txt", DocsFetcher.detect_source_type("https://react.dev/llms-small.txt")
  end

  test "detects openapi.json as openapi" do
    assert_equal "openapi", DocsFetcher.detect_source_type("https://api.example.com/openapi.json")
  end

  test "detects swagger.yaml as openapi" do
    assert_equal "openapi", DocsFetcher.detect_source_type("https://api.example.com/swagger.yaml")
  end

  test "detects swagger.yml as openapi" do
    assert_equal "openapi", DocsFetcher.detect_source_type("https://api.example.com/swagger.yml")
  end

  test "defaults to website for regular URLs" do
    assert_equal "website", DocsFetcher.detect_source_type("https://docs.example.com/getting-started")
  end

  test "defaults to website for invalid URIs" do
    assert_equal "website", DocsFetcher.detect_source_type("not a valid url at all ^^^")
  end

  test "detects github with trailing slash" do
    assert_equal "github", DocsFetcher.detect_source_type("https://github.com/vercel/next.js/")
  end

  test "detects llms.txt with query params" do
    assert_equal "llms_txt", DocsFetcher.detect_source_type("https://example.com/llms.txt?v=2")
  end

  test "detects openapi with api-docs path" do
    assert_equal "openapi", DocsFetcher.detect_source_type("https://api.example.com/api-docs")
  end

  test "detects openapi.yaml as openapi" do
    assert_equal "openapi", DocsFetcher.detect_source_type("https://api.example.com/v2/openapi.yaml")
  end

  test "defaults to website for empty string" do
    assert_equal "website", DocsFetcher.detect_source_type("")
  end

  test "defaults to website for URL with port" do
    assert_equal "website", DocsFetcher.detect_source_type("https://docs.example.com:8080/guide")
  end

  test "detects gitlab with subdomain pattern" do
    assert_equal "gitlab", DocsFetcher.detect_source_type("https://gitlab.internal.corp.com/team/project")
  end

  # --- for ---

  test "for returns Github fetcher" do
    assert_instance_of DocsFetcher::Github, DocsFetcher.for("github")
  end

  test "for returns Gitlab fetcher" do
    assert_instance_of DocsFetcher::Gitlab, DocsFetcher.for("gitlab")
  end

  test "for returns Website fetcher" do
    assert_instance_of DocsFetcher::Website, DocsFetcher.for("website")
  end

  test "for returns LlmsTxt fetcher" do
    assert_instance_of DocsFetcher::LlmsTxt, DocsFetcher.for("llms_txt")
  end

  test "for returns Openapi fetcher" do
    assert_instance_of DocsFetcher::Openapi, DocsFetcher.for("openapi")
  end

  test "for raises on unknown source type" do
    assert_raises(ArgumentError) { DocsFetcher.for("unknown") }
  end
end
