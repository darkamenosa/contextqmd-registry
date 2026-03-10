# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class DocsFetcher::GitTest < ActiveSupport::TestCase
  setup do
    @fetcher = DocsFetcher::Git.new
  end

  # --- URL normalization ---

  test "normalizes GitHub URL to .git URL" do
    result = @fetcher.send(:normalize_git_url, "https://github.com/rails/rails")
    assert_equal "https://github.com/rails/rails.git", result
  end

  test "normalizes GitHub URL with tree path" do
    result = @fetcher.send(:normalize_git_url, "https://github.com/rails/rails/tree/v8.1.2")
    assert_equal "https://github.com/rails/rails.git", result
  end

  test "normalizes GitHub URL with .git suffix" do
    result = @fetcher.send(:normalize_git_url, "https://github.com/facebook/react.git")
    assert_equal "https://github.com/facebook/react.git", result
  end

  test "normalizes GitLab URL" do
    result = @fetcher.send(:normalize_git_url, "https://gitlab.com/group/project")
    assert_equal "https://gitlab.com/group/project.git", result
  end

  test "normalizes GitLab URL with /-/ separator" do
    result = @fetcher.send(:normalize_git_url, "https://gitlab.com/group/project/-/tree/main")
    assert_equal "https://gitlab.com/group/project.git", result
  end

  test "normalizes Bitbucket URL" do
    result = @fetcher.send(:normalize_git_url, "https://bitbucket.org/owner/repo")
    assert_equal "https://bitbucket.org/owner/repo.git", result
  end

  test "normalizes Bitbucket URL with src path" do
    result = @fetcher.send(:normalize_git_url, "https://bitbucket.org/owner/repo/src/main")
    assert_equal "https://bitbucket.org/owner/repo.git", result
  end

  # --- Branch extraction ---

  test "extracts branch from GitHub tree URL" do
    branch = @fetcher.send(:extract_branch_from_url, "https://github.com/rails/rails/tree/v8.1.2")
    assert_equal "v8.1.2", branch
  end

  test "returns nil branch for GitHub URL without tree" do
    branch = @fetcher.send(:extract_branch_from_url, "https://github.com/rails/rails")
    assert_nil branch
  end

  test "extracts branch from GitLab URL" do
    branch = @fetcher.send(:extract_branch_from_url, "https://gitlab.com/group/project/-/tree/develop")
    assert_equal "develop", branch
  end

  test "extracts branch from Bitbucket URL" do
    branch = @fetcher.send(:extract_branch_from_url, "https://bitbucket.org/owner/repo/src/main")
    assert_equal "main", branch
  end

  test "returns nil for invalid URI" do
    branch = @fetcher.send(:extract_branch_from_url, "not a url ^^^")
    assert_nil branch
  end

  # --- Owner/repo extraction ---

  test "extracts owner and repo from GitHub URL" do
    owner, repo = @fetcher.send(:extract_owner_repo, "https://github.com/vercel/next.js")
    assert_equal "vercel", owner
    assert_equal "next.js", repo
  end

  test "extracts owner and repo from GitHub URL with .git" do
    owner, repo = @fetcher.send(:extract_owner_repo, "https://github.com/facebook/react.git")
    assert_equal "facebook", owner
    assert_equal "react", repo
  end

  test "extracts owner and repo from GitLab URL" do
    owner, repo = @fetcher.send(:extract_owner_repo, "https://gitlab.com/group/project")
    assert_equal "group", owner
    assert_equal "project", repo
  end

  test "extracts owner and repo from nested GitLab URL" do
    owner, repo = @fetcher.send(:extract_owner_repo, "https://gitlab.com/org/subgroup/project")
    assert_equal "org/subgroup", owner
    assert_equal "project", repo
  end

  test "extracts owner and repo from Bitbucket URL" do
    owner, repo = @fetcher.send(:extract_owner_repo, "https://bitbucket.org/team/repo")
    assert_equal "team", owner
    assert_equal "repo", repo
  end

  test "raises on URL with only host" do
    assert_raises(ArgumentError) do
      @fetcher.send(:extract_owner_repo, "https://github.com/")
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

  test "install files get bonus" do
    install_score = @fetcher.send(:score_file, "docs/install.md", 5000)
    plain_score = @fetcher.send(:score_file, "docs/other.md", 5000)
    assert install_score > plain_score, "Install files should score higher"
  end

  # --- Skip paths ---

  test "skip_path returns true for node_modules" do
    assert @fetcher.send(:skip_path?, "node_modules/foo/README.md")
  end

  test "skip_path returns true for test directories" do
    assert @fetcher.send(:skip_path?, "test/fixtures/README.md")
  end

  test "skip_path returns true for __tests__ directories" do
    assert @fetcher.send(:skip_path?, "src/__tests__/README.md")
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

  test "skip_path returns true for archived directories" do
    assert @fetcher.send(:skip_path?, "archive/old-docs/guide.md")
  end

  test "skip_path returns true for deprecated directories" do
    assert @fetcher.send(:skip_path?, "deprecated/api.md")
  end

  test "skip_path returns true for benchmark directories" do
    assert @fetcher.send(:skip_path?, "benchmarks/results.md")
  end

  test "skip_path returns true for lib/cjs pattern" do
    assert @fetcher.send(:skip_path?, "lib/cjs/README.md")
  end

  test "skip_path returns true for lib/esm pattern" do
    assert @fetcher.send(:skip_path?, "lib/esm/guide.md")
  end

  test "skip_path returns true for Chinese locale dirs" do
    assert @fetcher.send(:skip_path?, "docs/zh-cn/guide.md")
  end

  test "skip_path returns true for CODE_OF_CONDUCT" do
    assert @fetcher.send(:skip_path?, "CODE_OF_CONDUCT.md")
  end

  test "skip_path returns true for NEWS.md" do
    assert @fetcher.send(:skip_path?, "NEWS.md")
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

  test "doc extensions include markdown" do
    assert DocsFetcher::Git::DOC_EXTENSIONS.include?(".md")
    assert DocsFetcher::Git::DOC_EXTENSIONS.include?(".mdx")
  end

  test "doc extensions include html" do
    assert DocsFetcher::Git::DOC_EXTENSIONS.include?(".html")
  end

  test "doc extensions include rst" do
    assert DocsFetcher::Git::DOC_EXTENSIONS.include?(".rst")
  end

  test "doc extensions include ipynb" do
    assert DocsFetcher::Git::DOC_EXTENSIONS.include?(".ipynb")
  end

  # --- File discovery with tmpdir ---

  test "discover_doc_files finds markdown files" do
    Dir.mktmpdir("test-git-") do |tmpdir|
      FileUtils.mkdir_p(File.join(tmpdir, "docs"))
      File.write(File.join(tmpdir, "README.md"), "# Hello")
      File.write(File.join(tmpdir, "docs", "guide.md"), "# Guide\n\nContent here.")
      File.write(File.join(tmpdir, "src", "app.js").tap { |p| FileUtils.mkdir_p(File.dirname(p)) }, "code")

      candidates = @fetcher.send(:discover_doc_files, tmpdir)
      rel_paths = candidates.map { |c| @fetcher.send(:relative_path, c, tmpdir) }

      assert_includes rel_paths, "README.md"
      assert_includes rel_paths, "docs/guide.md"
      assert_not rel_paths.any? { |p| p.end_with?(".js") }
    end
  end

  test "discover_doc_files skips node_modules" do
    Dir.mktmpdir("test-git-") do |tmpdir|
      FileUtils.mkdir_p(File.join(tmpdir, "node_modules", "pkg"))
      File.write(File.join(tmpdir, "node_modules", "pkg", "README.md"), "# Pkg")

      candidates = @fetcher.send(:discover_doc_files, tmpdir)
      assert_empty candidates
    end
  end

  test "discover_doc_files skips empty files" do
    Dir.mktmpdir("test-git-") do |tmpdir|
      File.write(File.join(tmpdir, "empty.md"), "")

      candidates = @fetcher.send(:discover_doc_files, tmpdir)
      assert_empty candidates
    end
  end

  test "discover_doc_files skips .git directory" do
    Dir.mktmpdir("test-git-") do |tmpdir|
      FileUtils.mkdir_p(File.join(tmpdir, ".git", "objects"))
      File.write(File.join(tmpdir, ".git", "description.md"), "content")
      File.write(File.join(tmpdir, "README.md"), "# Hello")

      candidates = @fetcher.send(:discover_doc_files, tmpdir)
      rel_paths = candidates.map { |c| @fetcher.send(:relative_path, c, tmpdir) }

      assert_includes rel_paths, "README.md"
      assert_not rel_paths.any? { |p| p.start_with?(".git/") }
    end
  end

  test "discover_doc_files finds html and ipynb files" do
    Dir.mktmpdir("test-git-") do |tmpdir|
      FileUtils.mkdir_p(File.join(tmpdir, "docs"))
      File.write(File.join(tmpdir, "docs", "guide.html"), "<html><body><h1>Guide</h1></body></html>")
      File.write(File.join(tmpdir, "docs", "notebook.ipynb"), '{"cells":[],"metadata":{}}')

      candidates = @fetcher.send(:discover_doc_files, tmpdir)
      rel_paths = candidates.map { |c| @fetcher.send(:relative_path, c, tmpdir) }

      assert_includes rel_paths, "docs/guide.html"
      assert_includes rel_paths, "docs/notebook.ipynb"
    end
  end

  # --- score_and_rank ---

  test "score_and_rank orders by score descending" do
    Dir.mktmpdir("test-git-") do |tmpdir|
      FileUtils.mkdir_p(File.join(tmpdir, "docs"))
      FileUtils.mkdir_p(File.join(tmpdir, "lib"))
      File.write(File.join(tmpdir, "README.md"), "# Hello\n\n" + ("content " * 500))
      File.write(File.join(tmpdir, "docs", "getting-started.md"), "# Getting Started\n\n" + ("content " * 500))
      File.write(File.join(tmpdir, "lib", "internal.md"), "# Internal\n\n" + ("content " * 500))

      candidates = @fetcher.send(:discover_doc_files, tmpdir)
      ranked = @fetcher.send(:score_and_rank, candidates, tmpdir)
      paths = ranked.map { |r| @fetcher.send(:relative_path, r[:path], tmpdir) }

      assert_equal "docs/getting-started.md", paths.first
      assert_equal "README.md", paths.second
      assert_equal "lib/internal.md", paths.last
    end
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

  test "extract_title finds frontmatter title" do
    content = "---\ntitle: My Guide\n---\n\n# Heading\n\nContent."
    title = @fetcher.send(:extract_title, content, "guide.md")
    assert_equal "My Guide", title
  end

  test "extract_title humanizes filename when no heading found" do
    content = "Just text, no heading."
    title = @fetcher.send(:extract_title, content, "getting-started.md")
    assert_equal "Getting Started", title
  end

  test "extract_title skips instruction-like headings" do
    content = "# Install the package\n\n## Real Title\n\nContent."
    title = @fetcher.send(:extract_title, content, "setup.md")
    assert_equal "Setup", title
  end

  # --- Content conversion ---

  test "convert_content passes through markdown" do
    content, title = @fetcher.send(:convert_content, "# Hello\n\nWorld", ".md")
    assert_equal "# Hello\n\nWorld", content
    assert_nil title
  end

  test "convert_content passes through rst" do
    content, title = @fetcher.send(:convert_content, "Hello\n=====\n\nWorld", ".rst")
    assert_equal "Hello\n=====\n\nWorld", content
    assert_nil title
  end

  test "convert_content converts ipynb" do
    notebook = {
      "cells" => [
        { "cell_type" => "markdown", "source" => [ "# Notebook Title\n", "\n", "Some text." ] },
        { "cell_type" => "code", "source" => [ "print('hello')" ] }
      ],
      "metadata" => {
        "kernelspec" => { "language" => "python" }
      }
    }.to_json

    content, _title = @fetcher.send(:convert_content, notebook, ".ipynb")
    assert_includes content, "# Notebook Title"
    assert_includes content, "```python"
    assert_includes content, "print('hello')"
    assert_includes content, "```"
  end

  test "convert_content handles empty ipynb cells" do
    notebook = {
      "cells" => [
        { "cell_type" => "markdown", "source" => [ "" ] },
        { "cell_type" => "code", "source" => [ "" ] }
      ],
      "metadata" => {}
    }.to_json

    content, _title = @fetcher.send(:convert_content, notebook, ".ipynb")
    assert_equal "", content.strip
  end

  test "convert_content handles invalid ipynb JSON" do
    content, _title = @fetcher.send(:convert_content, "not json at all", ".ipynb")
    assert_nil content
  end

  # --- HEAD SHA reading ---

  test "read_head_sha returns nil for missing .git directory" do
    Dir.mktmpdir("test-git-") do |tmpdir|
      sha = @fetcher.send(:read_head_sha, tmpdir)
      assert_nil sha
    end
  end

  test "read_head_sha reads detached HEAD" do
    Dir.mktmpdir("test-git-") do |tmpdir|
      FileUtils.mkdir_p(File.join(tmpdir, ".git"))
      File.write(File.join(tmpdir, ".git", "HEAD"), "abc123def456")

      sha = @fetcher.send(:read_head_sha, tmpdir)
      assert_equal "abc123def456", sha
    end
  end

  test "read_head_sha follows ref" do
    Dir.mktmpdir("test-git-") do |tmpdir|
      FileUtils.mkdir_p(File.join(tmpdir, ".git", "refs", "heads"))
      File.write(File.join(tmpdir, ".git", "HEAD"), "ref: refs/heads/main")
      File.write(File.join(tmpdir, ".git", "refs", "heads", "main"), "deadbeef123")

      sha = @fetcher.send(:read_head_sha, tmpdir)
      assert_equal "deadbeef123", sha
    end
  end

  # --- Strip frontmatter ---

  test "strip_frontmatter removes YAML frontmatter" do
    content = "---\ntitle: Test\n---\n\n# Hello"
    result = @fetcher.send(:strip_frontmatter, content)
    assert_equal "# Hello", result
  end

  test "strip_frontmatter leaves non-frontmatter content alone" do
    content = "# Hello\n\nWorld"
    result = @fetcher.send(:strip_frontmatter, content)
    assert_equal content, result
  end

  # --- Build file URL ---

  test "builds GitHub file URL" do
    url = @fetcher.send(:build_file_url, "https://github.com/rails/rails", "github.com", "docs/guide.md", "main")
    assert_equal "https://github.com/rails/rails/blob/main/docs/guide.md", url
  end

  test "builds GitLab file URL" do
    url = @fetcher.send(:build_file_url, "https://gitlab.com/group/project", "gitlab.com", "docs/guide.md", "main")
    assert_equal "https://gitlab.com/group/project/-/blob/main/docs/guide.md", url
  end

  test "builds Bitbucket file URL" do
    url = @fetcher.send(:build_file_url, "https://bitbucket.org/owner/repo", "bitbucket.org", "docs/guide.md", "main")
    assert_equal "https://bitbucket.org/owner/repo/src/main/docs/guide.md", url
  end

  # --- Result building ---

  test "build_result creates correct Result" do
    pages = [
      { page_uid: "readme", path: "README.md", title: "Readme", url: "https://example.com", content: "# Hi", headings: [] }
    ]
    result = @fetcher.send(:build_result, "owner", "my-lib", "https://github.com/owner/my-lib", pages, "1.0.0")

    assert_instance_of DocsFetcher::Result, result
    assert_equal "owner", result.namespace
    assert_equal "my-lib", result.name
    assert_equal "My Lib", result.display_name
    assert_equal "1.0.0", result.version
    assert_equal 1, result.pages.size
    assert_includes result.aliases, "my-lib"
    assert_includes result.aliases, "mylib"
  end

  # --- Fetcher dispatch ---

  test "DocsFetcher.for returns Git instance for git source_type" do
    fetcher = DocsFetcher.for("git")
    assert_instance_of DocsFetcher::Git, fetcher
  end
end
