# frozen_string_literal: true

require "test_helper"

class DocsFetcher::GitlabTest < ActiveSupport::TestCase
  setup do
    @fetcher = DocsFetcher::Gitlab.new
  end

  # --- URL parsing ---

  test "parses standard GitLab URL" do
    host, project_path, branch = @fetcher.send(:parse_gitlab_url, "https://gitlab.com/group/project")
    assert_equal "gitlab.com", host
    assert_equal "group/project", project_path
    assert_nil branch
  end

  test "parses GitLab URL with /-/ separator and branch" do
    host, project_path, branch = @fetcher.send(:parse_gitlab_url, "https://gitlab.com/group/project/-/tree/main")
    assert_equal "gitlab.com", host
    assert_equal "group/project", project_path
    assert_equal "main", branch
  end

  test "parses nested GitLab project path" do
    host, project_path, branch = @fetcher.send(:parse_gitlab_url, "https://gitlab.com/org/subgroup/project")
    assert_equal "gitlab.com", host
    assert_equal "org/subgroup/project", project_path
    assert_nil branch
  end

  test "parses self-hosted GitLab URL" do
    host, project_path, branch = @fetcher.send(:parse_gitlab_url, "https://git.company.com/team/repo/-/tree/develop")
    assert_equal "git.company.com", host
    assert_equal "team/repo", project_path
    assert_equal "develop", branch
  end

  test "raises on invalid GitLab URL with only one path segment" do
    assert_raises(ArgumentError) do
      @fetcher.send(:parse_gitlab_url, "https://gitlab.com/just-owner")
    end
  end

  # --- File scoring ---

  test "root README.md gets high score" do
    score = @fetcher.send(:score_file, "README.md")
    assert score >= 100, "Root README.md should score >= 100, got #{score}"
  end

  test "docs directory files score higher than random files" do
    doc_score = @fetcher.send(:score_file, "docs/getting-started.md")
    random_score = @fetcher.send(:score_file, "lib/internal/utils.md")
    assert doc_score > random_score, "docs/ files should score higher"
  end

  test "getting-started files get bonus score" do
    score = @fetcher.send(:score_file, "docs/getting-started.md")
    plain_score = @fetcher.send(:score_file, "docs/other-page.md")
    assert score > plain_score, "Getting started should score higher than plain doc"
  end

  test "deep paths get depth penalty" do
    shallow_score = @fetcher.send(:score_file, "docs/guide.md")
    deep_score = @fetcher.send(:score_file, "docs/a/b/c/d/guide.md")
    assert shallow_score > deep_score, "Deeper files should score lower"
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

  test "skip_path returns false for regular doc files" do
    assert_not @fetcher.send(:skip_path?, "docs/getting-started.md")
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
  end

  # --- File discovery ---

  test "discover_doc_files filters tree items correctly" do
    tree = [
      { "type" => "blob", "path" => "docs/guide.md" },
      { "type" => "blob", "path" => "README.md" },
      { "type" => "blob", "path" => "node_modules/pkg/README.md" },
      { "type" => "blob", "path" => "CHANGELOG.md" },
      { "type" => "tree", "path" => "docs" },
      { "type" => "blob", "path" => "src/app.js" }
    ]

    candidates = @fetcher.send(:discover_doc_files, tree)
    paths = candidates.map { |c| c["path"] }

    assert_includes paths, "docs/guide.md"
    assert_includes paths, "README.md"
    assert_not_includes paths, "node_modules/pkg/README.md"
    assert_not_includes paths, "CHANGELOG.md"
    assert_not_includes paths, "src/app.js"
  end

  # --- Version extraction ---

  test "extract_version parses v-prefixed branch" do
    assert_equal "8.1.2", @fetcher.send(:extract_version, "v8.1.2")
  end

  test "extract_version parses release branch" do
    assert_equal "3.0", @fetcher.send(:extract_version, "release/3.0")
  end

  test "extract_version returns nil for main branch" do
    assert_nil @fetcher.send(:extract_version, "main")
  end

  test "extract_version returns nil when branch is nil" do
    assert_nil @fetcher.send(:extract_version, nil)
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
      { "path" => "lib/internal.md" },
      { "path" => "docs/getting-started.md" },
      { "path" => "README.md" }
    ]

    ranked = @fetcher.send(:score_and_rank, candidates)
    paths = ranked.map { |r| r["path"] }

    assert_equal "docs/getting-started.md", paths.first
    assert_equal "README.md", paths.second
    assert_equal "lib/internal.md", paths.last
  end

  # --- Fetcher dispatch ---

  test "DocsFetcher.for returns Gitlab instance for gitlab source_type" do
    fetcher = DocsFetcher.for("gitlab")
    assert_instance_of DocsFetcher::Gitlab, fetcher
  end
end
