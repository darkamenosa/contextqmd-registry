# frozen_string_literal: true

require "test_helper"

# Integration tests that clone real repos and verify crawl output.
# These are slower (~30s each) because they hit the network.
# Run with: bin/rails test test/models/docs_fetcher/git_integration_test.rb
class DocsFetcher::GitIntegrationTest < ActiveSupport::TestCase
  CrawlStub = Struct.new(:url, :source_type, :library_id, :library, keyword_init: true)

  def crawl(url)
    req = CrawlStub.new(url: url, source_type: "github", library_id: nil, library: nil)
    DocsFetcher::Git::Github.new.fetch(req)
  end

  # --- socket.io: .io in repo name should NOT trigger docs-repo stripping ---

  test "socketio/socket.io: slug is socket-io, not socket" do
    result = crawl("https://github.com/socketio/socket.io")

    assert_equal "socket-io", result.slug
    assert_equal "Socket Io", result.display_name
    assert result.version.present?, "Expected latest stable tag version"
    assert_equal "stable", Version.channel_for(result.version)
    assert_operator result.pages.size, :>=, 40

    paths = result.pages.map { |p| p[:path] }

    # Protocol docs from docs/ must be present (they exist on main, not tags)
    assert paths.any? { |p| p.start_with?("docs/socket.io-protocol/") },
           "Expected socket.io-protocol docs, got: #{paths.select { |p| p.start_with?("docs/") }}"
    assert paths.any? { |p| p.start_with?("docs/engine.io-protocol/") },
           "Expected engine.io-protocol docs"

    # Examples should be included (not excluded)
    assert paths.any? { |p| p.start_with?("examples/") },
           "Expected examples/ to be included"
  end

  # --- inertia-rails: normal repo, should work cleanly ---

  test "inertiajs/inertia-rails: correct slug, version, has docs/" do
    result = crawl("https://github.com/inertiajs/inertia-rails")

    assert_equal "inertia-rails", result.slug
    assert_equal "Inertia Rails", result.display_name
    assert result.version.present?, "Expected a version"
    assert_operator result.pages.size, :>=, 20

    paths = result.pages.map { |p| p[:path] }
    assert paths.any? { |p| p.start_with?("docs/") }, "Expected docs/ pages"
  end

  # --- zed: absurd version tags (0.999999.0, 0.9999-temporary) must be skipped ---

  test "zed-industries/zed: version is reasonable, not 0.999999.0" do
    result = crawl("https://github.com/zed-industries/zed")

    assert_equal "zed", result.slug
    assert_equal "Zed", result.display_name

    # Must not pick absurd tags
    refute_match(/999/, result.version.to_s, "Version #{result.version} looks absurd")
    assert result.version.present?

    assert_operator result.pages.size, :>=, 100

    paths = result.pages.map { |p| p[:path] }

    # Real docs from docs/src/ must be present
    assert paths.any? { |p| p.start_with?("docs/src/") },
           "Expected docs/src/ pages (actual docs)"

    # Excluded dirs must not appear
    refute paths.any? { |p| p.start_with?("legal/") }, "legal/ should be excluded"
    refute paths.any? { |p| File.basename(p) == "CLAUDE.md" }, "CLAUDE.md should be excluded"
    refute paths.any? { |p| File.basename(p) == "AGENTS.md" }, "AGENTS.md should be excluded"
  end

  # --- node-postgres: small repo with docs website in docs/pages/ ---

  test "brianc/node-postgres: correct slug, has docs" do
    result = crawl("https://github.com/brianc/node-postgres")

    assert_equal "node-postgres", result.slug
    assert_equal "Node Postgres", result.display_name
    assert result.version.present?
    assert_operator result.pages.size, :>=, 10

    paths = result.pages.map { |p| p[:path] }
    assert paths.any? { |p| p.start_with?("docs/") }, "Expected docs/ pages"
  end

  # --- fish-shell: previously failed with "Title can't be blank" ---

  test "fish-shell/fish-shell: all pages have non-blank titles" do
    result = crawl("https://github.com/fish-shell/fish-shell")

    assert_equal "fish-shell", result.slug
    assert_equal "Fish Shell", result.display_name
    assert result.version.present?
    refute_match(/999/, result.version.to_s)
    assert_operator result.pages.size, :>=, 50

    # Every page must have a non-blank title (the bug that caused production failure)
    result.pages.each do |page|
      assert page[:title].present?, "Page #{page[:path]} has blank title: #{page[:title].inspect}"
    end

    paths = result.pages.map { |p| p[:path] }
    assert paths.any? { |p| p.start_with?("doc_src/") }, "Expected doc_src/ pages"
  end

  # --- flask-cors: tiny repo, RST readme, few docs ---

  test "corydolphin/flask-cors: correct slug, has docs" do
    result = crawl("https://github.com/corydolphin/flask-cors")

    assert_equal "flask-cors", result.slug
    assert_equal "Flask Cors", result.display_name
    assert result.version.present?
    assert_operator result.pages.size, :>=, 4

    paths = result.pages.map { |p| p[:path] }
    assert paths.any? { |p| p.start_with?("docs/") }, "Expected docs/ pages"

    # Should include .rst files
    assert paths.any? { |p| p.end_with?(".rst") }, "Expected .rst files (README.rst)"
  end
end
