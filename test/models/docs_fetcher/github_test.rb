# frozen_string_literal: true

require "test_helper"

class DocsFetcher::GithubTest < ActiveSupport::TestCase
  setup do
    @fetcher = DocsFetcher::Github.new
  end

  # --- URL parsing ---

  test "parses standard GitHub URL" do
    owner, repo, branch = @fetcher.send(:parse_github_url, "https://github.com/vercel/next.js")
    assert_equal "vercel", owner
    assert_equal "next.js", repo  # only .git suffix is stripped, not .js
    assert_nil branch
  end

  test "parses GitHub URL with branch" do
    owner, repo, branch = @fetcher.send(:parse_github_url, "https://github.com/rails/rails/tree/main")
    assert_equal "rails", owner
    assert_equal "rails", repo
    assert_equal "main", branch
  end

  test "parses URL with .git suffix" do
    owner, repo, branch = @fetcher.send(:parse_github_url, "https://github.com/facebook/react.git")
    assert_equal "facebook", owner
    assert_equal "react", repo
    assert_nil branch
  end

  test "raises on invalid GitHub URL" do
    assert_raises(ArgumentError) do
      @fetcher.send(:parse_github_url, "https://github.com/")
    end
  end

  test "raises on URL with only owner" do
    assert_raises(ArgumentError) do
      @fetcher.send(:parse_github_url, "https://github.com/vercel")
    end
  end

  # --- File scoring ---

  test "root README.md gets high score" do
    score = @fetcher.send(:score_file, "README.md", 5000)
    assert score >= 100, "Root README.md should score >= 100, got #{score}"
  end

  test "docs directory files score higher than random files" do
    doc_score = @fetcher.send(:score_file, "docs/getting-started.md", 5000)
    random_score = @fetcher.send(:score_file, "lib/internal/utils.md", 5000)
    assert doc_score > random_score, "docs/ files should score higher"
  end

  test "getting-started files get bonus score" do
    score = @fetcher.send(:score_file, "docs/getting-started.md", 5000)
    plain_score = @fetcher.send(:score_file, "docs/other-page.md", 5000)
    assert score > plain_score, "Getting started should score higher than plain doc"
  end

  test "very small files get penalty" do
    small_score = @fetcher.send(:score_file, "docs/intro.md", 100)
    normal_score = @fetcher.send(:score_file, "docs/intro.md", 5000)
    assert normal_score > small_score, "Very small files should be penalized"
  end

  test "deep paths get depth penalty" do
    shallow_score = @fetcher.send(:score_file, "docs/guide.md", 5000)
    deep_score = @fetcher.send(:score_file, "docs/a/b/c/d/guide.md", 5000)
    assert shallow_score > deep_score, "Deeper files should score lower"
  end

  test "release notes get penalty" do
    release_score = @fetcher.send(:score_file, "docs/release-notes.md", 5000)
    normal_score = @fetcher.send(:score_file, "docs/guide.md", 5000)
    assert normal_score > release_score, "Release notes should be penalized"
  end

  test "tutorial files get bonus" do
    tutorial_score = @fetcher.send(:score_file, "docs/tutorial.md", 5000)
    plain_score = @fetcher.send(:score_file, "docs/other.md", 5000)
    assert tutorial_score > plain_score, "Tutorial files should score higher"
  end

  # --- Skip paths ---

  test "skip_path returns true for node_modules" do
    assert @fetcher.send(:skip_path?, "node_modules/foo/README.md")
  end

  test "skip_path returns true for test directories" do
    assert @fetcher.send(:skip_path?, "test/fixtures/README.md")
  end

  test "skip_path returns true for CHANGELOG" do
    assert @fetcher.send(:skip_path?, "CHANGELOG.md")
  end

  test "skip_path returns true for LICENSE" do
    assert @fetcher.send(:skip_path?, "LICENSE.md")
  end

  test "skip_path returns true for vendor directory" do
    assert @fetcher.send(:skip_path?, "vendor/bundle/README.md")
  end

  test "skip_path returns true for build output" do
    assert @fetcher.send(:skip_path?, "dist/docs/readme.md")
  end

  test "skip_path returns false for regular doc files" do
    assert_not @fetcher.send(:skip_path?, "docs/getting-started.md")
  end

  test "skip_path returns false for root README" do
    assert_not @fetcher.send(:skip_path?, "README.md")
  end

  test "skip_path is case-insensitive for filenames" do
    assert @fetcher.send(:skip_path?, "changelog.md")
  end

  # --- Doc extension detection ---

  test "doc_extension recognizes markdown files" do
    assert @fetcher.send(:doc_extension?, "guide.md")
    assert @fetcher.send(:doc_extension?, "guide.mdx")
    assert @fetcher.send(:doc_extension?, "guide.rst")
  end

  test "doc_extension rejects non-doc files" do
    assert_not @fetcher.send(:doc_extension?, "app.js")
    assert_not @fetcher.send(:doc_extension?, "style.css")
    assert_not @fetcher.send(:doc_extension?, "data.json")
  end

  # --- File discovery ---

  test "discover_doc_files filters tree items correctly" do
    tree = [
      { "type" => "blob", "path" => "docs/guide.md", "size" => 5000 },
      { "type" => "blob", "path" => "README.md", "size" => 3000 },
      { "type" => "blob", "path" => "node_modules/pkg/README.md", "size" => 1000 },
      { "type" => "blob", "path" => "CHANGELOG.md", "size" => 20_000 },
      { "type" => "tree", "path" => "docs" },
      { "type" => "blob", "path" => "src/app.js", "size" => 5000 },
      { "type" => "blob", "path" => "docs/empty.md", "size" => 0 }
    ]

    candidates = @fetcher.send(:discover_doc_files, tree)
    paths = candidates.map { |c| c["path"] }

    assert_includes paths, "docs/guide.md"
    assert_includes paths, "README.md"
    assert_not_includes paths, "node_modules/pkg/README.md"
    assert_not_includes paths, "CHANGELOG.md"
    assert_not_includes paths, "src/app.js"
    assert_not_includes paths, "docs/empty.md"
  end

  # --- Version extraction ---

  test "extract_version parses v-prefixed branch" do
    assert_equal "8.1.2", @fetcher.send(:extract_version, "v8.1.2", {})
  end

  test "extract_version parses release branch" do
    assert_equal "3.0", @fetcher.send(:extract_version, "release/3.0", {})
  end

  test "extract_version returns nil for main branch" do
    assert_nil @fetcher.send(:extract_version, "main", {})
  end

  test "extract_version returns nil when branch is nil" do
    assert_nil @fetcher.send(:extract_version, nil, {})
  end

  # --- Title extraction ---

  test "extract_title finds ATX heading" do
    content = "# Getting Started\n\nSome content."
    title = @fetcher.send(:extract_title, content, "getting-started.md")
    assert_equal "Getting Started", title
  end

  test "extract_title humanizes filename when no heading found" do
    content = "Just text, no heading."
    title = @fetcher.send(:extract_title, content, "getting-started.md")
    assert_equal "Getting Started", title
  end

  # --- score_and_rank ---

  test "score_and_rank orders by score descending" do
    candidates = [
      { "path" => "lib/internal.md", "size" => 5000 },
      { "path" => "docs/getting-started.md", "size" => 5000 },
      { "path" => "README.md", "size" => 5000 }
    ]

    ranked = @fetcher.send(:score_and_rank, candidates)
    paths = ranked.map { |r| r["path"] }

    # docs/getting-started.md should be first (high-value dir + getting-started bonus),
    # README.md second, lib/ last
    assert_equal "docs/getting-started.md", paths.first
    assert_equal "README.md", paths.second
    assert_equal "lib/internal.md", paths.last
  end
end
