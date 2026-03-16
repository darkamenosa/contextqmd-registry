# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class DocsFetcher::GitTest < ActiveSupport::TestCase
  setup do
    @github = DocsFetcher::Git::Github.new
    @gitlab = DocsFetcher::Git::Gitlab.new
    @bitbucket = DocsFetcher::Git::Bitbucket.new
    @generic = DocsFetcher::Git.new
  end

  # --- GitHub URL normalization ---

  test "normalizes GitHub URL to .git URL" do
    result = @github.send(:normalize_git_url, "https://github.com/rails/rails")
    assert_equal "https://github.com/rails/rails.git", result
  end

  test "normalizes GitHub URL with tree path" do
    result = @github.send(:normalize_git_url, "https://github.com/rails/rails/tree/v8.1.2")
    assert_equal "https://github.com/rails/rails.git", result
  end

  test "normalizes GitHub URL with .git suffix" do
    result = @github.send(:normalize_git_url, "https://github.com/facebook/react.git")
    assert_equal "https://github.com/facebook/react.git", result
  end

  # --- GitLab URL normalization ---

  test "normalizes GitLab URL" do
    result = @gitlab.send(:normalize_git_url, "https://gitlab.com/group/project")
    assert_equal "https://gitlab.com/group/project.git", result
  end

  test "normalizes GitLab URL with /-/ separator" do
    result = @gitlab.send(:normalize_git_url, "https://gitlab.com/group/project/-/tree/main")
    assert_equal "https://gitlab.com/group/project.git", result
  end

  # --- Bitbucket URL normalization ---

  test "normalizes Bitbucket URL" do
    result = @bitbucket.send(:normalize_git_url, "https://bitbucket.org/owner/repo")
    assert_equal "https://bitbucket.org/owner/repo.git", result
  end

  test "normalizes Bitbucket URL with src path" do
    result = @bitbucket.send(:normalize_git_url, "https://bitbucket.org/owner/repo/src/main")
    assert_equal "https://bitbucket.org/owner/repo.git", result
  end

  # --- Branch extraction ---

  test "extracts branch from GitHub tree URL" do
    branch = @github.send(:extract_branch_from_url, "https://github.com/rails/rails/tree/v8.1.2")
    assert_equal "v8.1.2", branch
  end

  test "returns nil branch for GitHub URL without tree" do
    branch = @github.send(:extract_branch_from_url, "https://github.com/rails/rails")
    assert_nil branch
  end

  test "extracts branch from GitLab URL" do
    branch = @gitlab.send(:extract_branch_from_url, "https://gitlab.com/group/project/-/tree/develop")
    assert_equal "develop", branch
  end

  test "extracts branch from Bitbucket URL" do
    branch = @bitbucket.send(:extract_branch_from_url, "https://bitbucket.org/owner/repo/src/main")
    assert_equal "main", branch
  end

  test "returns nil branch for generic git URL" do
    branch = @generic.send(:extract_branch_from_url, "https://git.example.com/owner/repo")
    assert_nil branch
  end

  test "returns nil for invalid URI" do
    branch = @github.send(:extract_branch_from_url, "not a url ^^^")
    assert_nil branch
  end

  # --- Owner/repo extraction ---

  test "extracts owner and repo from GitHub URL" do
    owner, repo = @github.send(:extract_owner_repo, "https://github.com/vercel/next.js")
    assert_equal "vercel", owner
    assert_equal "next.js", repo
  end

  test "extracts owner and repo from GitHub URL with .git" do
    owner, repo = @github.send(:extract_owner_repo, "https://github.com/facebook/react.git")
    assert_equal "facebook", owner
    assert_equal "react", repo
  end

  test "extracts owner and repo from GitLab URL" do
    owner, repo = @gitlab.send(:extract_owner_repo, "https://gitlab.com/group/project")
    assert_equal "group", owner
    assert_equal "project", repo
  end

  test "extracts owner and repo from nested GitLab URL" do
    owner, repo = @gitlab.send(:extract_owner_repo, "https://gitlab.com/org/subgroup/project")
    assert_equal "org/subgroup", owner
    assert_equal "project", repo
  end

  test "extracts owner and repo from Bitbucket URL" do
    owner, repo = @bitbucket.send(:extract_owner_repo, "https://bitbucket.org/team/repo")
    assert_equal "team", owner
    assert_equal "repo", repo
  end

  test "raises on URL with only host" do
    assert_raises(ArgumentError) do
      @generic.send(:extract_owner_repo, "https://github.com/")
    end
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

      candidates = @generic.send(:discover_doc_files, tmpdir)
      rel_paths = candidates.map { |c| c.sub("#{tmpdir}/", "") }

      assert_includes rel_paths, "README.md"
      assert_includes rel_paths, "docs/guide.md"
      assert_not rel_paths.any? { |p| p.end_with?(".js") }
    end
  end

  test "discover_doc_files skips empty files" do
    Dir.mktmpdir("test-git-") do |tmpdir|
      File.write(File.join(tmpdir, "empty.md"), "")

      candidates = @generic.send(:discover_doc_files, tmpdir)
      assert_empty candidates
    end
  end

  test "discover_doc_files skips .git directory" do
    Dir.mktmpdir("test-git-") do |tmpdir|
      FileUtils.mkdir_p(File.join(tmpdir, ".git", "objects"))
      File.write(File.join(tmpdir, ".git", "description.md"), "content")
      File.write(File.join(tmpdir, "README.md"), "# Hello")

      candidates = @generic.send(:discover_doc_files, tmpdir)
      rel_paths = candidates.map { |c| c.sub("#{tmpdir}/", "") }

      assert_includes rel_paths, "README.md"
      assert_not rel_paths.any? { |p| p.start_with?(".git/") }
    end
  end

  test "discover_doc_files finds html and ipynb files" do
    Dir.mktmpdir("test-git-") do |tmpdir|
      FileUtils.mkdir_p(File.join(tmpdir, "docs"))
      File.write(File.join(tmpdir, "docs", "guide.html"), "<html><body><h1>Guide</h1></body></html>")
      File.write(File.join(tmpdir, "docs", "notebook.ipynb"), '{"cells":[],"metadata":{}}')

      candidates = @generic.send(:discover_doc_files, tmpdir)
      rel_paths = candidates.map { |c| c.sub("#{tmpdir}/", "") }

      assert_includes rel_paths, "docs/guide.html"
      assert_includes rel_paths, "docs/notebook.ipynb"
    end
  end

  test "build_pages preserves nested path structure in page_uids to avoid collisions" do
    Dir.mktmpdir("test-git-") do |tmpdir|
      first = File.join(tmpdir, "docs", "foo", "bar.md")
      second = File.join(tmpdir, "docs", "foo-bar.md")

      FileUtils.mkdir_p(File.dirname(first))
      File.write(first, "# Nested")
      File.write(second, "# Flat")

      pages = @generic.send(
        :build_pages,
        [ first, second ],
        tmpdir,
        "https://github.com/example/repo",
        "main"
      )

      assert_equal 2, pages.size
      assert_equal 2, pages.map { |page| page[:page_uid] }.uniq.size
      assert_includes pages.map { |page| page[:page_uid] }, "docs/foo/bar"
      assert_includes pages.map { |page| page[:page_uid] }, "docs/foo-bar"
    end
  end

  test "build_pages scrubs invalid utf-8 bytes instead of raising" do
    Dir.mktmpdir("test-git-") do |tmpdir|
      path = File.join(tmpdir, "README.md")
      File.binwrite(path, "# Hello\xFF\nWorld")

      pages = nil
      assert_nothing_raised do
        pages = @generic.send(
          :build_pages,
          [ path ],
          tmpdir,
          "https://github.com/example/repo",
          "main"
        )
      end

      assert_equal 1, pages.size
      assert_equal "# Hello\nWorld", pages.first[:content]
    end
  end

  # --- Version extraction ---

  test "extract_version parses v-prefixed branch" do
    assert_equal "8.1.2", @generic.send(:extract_version, "v8.1.2")
  end

  test "extract_version parses release branch" do
    assert_equal "3.0", @generic.send(:extract_version, "release/3.0")
  end

  test "extract_version returns nil for main branch" do
    assert_nil @generic.send(:extract_version, "main")
  end

  test "extract_version returns nil when branch is nil" do
    assert_nil @generic.send(:extract_version, nil)
  end

  test "resolve_latest_tag prefers the highest stable tag" do
    @generic.define_singleton_method(:list_remote_tags) do |_repo_url|
      %w[v1.9.0 v2.0.0-rc1 v1.10.0]
    end

    assert_equal "v1.10.0", @generic.send(:resolve_latest_tag, "https://example.com/org/repo.git")
  end

  test "resolve_latest_tag skips absurd version tags" do
    @generic.define_singleton_method(:list_remote_tags) do |_repo_url|
      %w[v1.2.0 v0.999999.0 v999.9.9 v54011 v3.0.0]
    end

    assert_equal "v3.0.0", @generic.send(:resolve_latest_tag, "https://example.com/org/repo.git")
  end

  test "absurd_version? rejects high numeric segments" do
    assert @generic.send(:absurd_version?, "0.999999.0")
    assert @generic.send(:absurd_version?, "0.9999-temporary")
    assert @generic.send(:absurd_version?, "999.9.9")
    assert @generic.send(:absurd_version?, "54011")
    assert @generic.send(:absurd_version?, "2024.1.300751-latest")
  end

  test "absurd_version? allows normal versions" do
    refute @generic.send(:absurd_version?, "3.14.2")
    refute @generic.send(:absurd_version?, "2026.3.1")
    refute @generic.send(:absurd_version?, "16.1.6")
    refute @generic.send(:absurd_version?, "0.135.1")
    refute @generic.send(:absurd_version?, "0.227.1")
    refute @generic.send(:absurd_version?, "1.0.0-beta.1")
  end

  # --- Title extraction ---

  test "extract_title finds ATX heading" do
    content = "# Getting Started\n\nSome content."
    title = @generic.send(:extract_title, content, "getting-started.md")
    assert_equal "Getting Started", title
  end

  test "extract_title finds frontmatter title" do
    content = "---\ntitle: My Guide\n---\n\n# Heading\n\nContent."
    title = @generic.send(:extract_title, content, "guide.md")
    assert_equal "My Guide", title
  end

  test "extract_title humanizes filename when no heading found" do
    content = "Just text, no heading."
    title = @generic.send(:extract_title, content, "getting-started.md")
    assert_equal "Getting Started", title
  end

  test "extract_title skips instruction-like headings" do
    content = "# Install the package\n\n## Real Title\n\nContent."
    title = @generic.send(:extract_title, content, "setup.md")
    assert_equal "Setup", title
  end

  test "extract_title strips linked badges from linked headings" do
    content = <<~MD
      # [React](https://react.dev/) &middot; [![GitHub license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/facebook/react/blob/main/LICENSE) [![npm version](https://img.shields.io/npm/v/react.svg?style=flat)](https://www.npmjs.com/package/react)
    MD

    title = @generic.send(:extract_title, content, "README.md")

    assert_equal "React ·", title
  end

  # --- Content conversion ---

  test "convert_content passes through markdown" do
    content, title = @generic.send(:convert_content, "# Hello\n\nWorld", ".md")
    assert_equal "# Hello\n\nWorld", content
    assert_nil title
  end

  test "convert_content extracts title from rst underline heading" do
    content, title = @generic.send(:convert_content, "Hello World\n===========\n\nSome text.", ".rst")
    assert_equal "Hello World\n===========\n\nSome text.", content
    assert_equal "Hello World", title
  end

  test "convert_content extracts rst title with link markup stripped" do
    rst = "`fish <https://fishshell.com/>`__ - the friendly interactive shell |Build Status|\n" \
          "=================================================================================\n\nContent."
    _content, title = @generic.send(:convert_content, rst, ".rst")
    assert_equal "fish - the friendly interactive shell", title
  end

  test "convert_content returns nil title for rst without heading" do
    content, title = @generic.send(:convert_content, "Just plain text\nno underline here", ".rst")
    assert_equal "Just plain text\nno underline here", content
    assert_nil title
  end

  test "extract_rst_headings returns sub-headings skipping the title" do
    rst = <<~RST
      Document Title
      ==============

      Some intro.

      Section One
      -----------

      Content here.

      Section Two
      -----------

      More content.

      Subsection
      ~~~~~~~~~~

      Details.
    RST
    headings = @generic.send(:extract_rst_headings, rst, "Document Title")
    assert_equal [ "Section One", "Section Two", "Subsection" ], headings
  end

  test "extract_rst_headings returns empty for single-heading rst" do
    rst = "Title Only\n==========\n\nJust content, no sub-headings."
    headings = @generic.send(:extract_rst_headings, rst, "Title Only")
    assert_empty headings
  end

  test "extract_rst_headings keeps first section when title differs" do
    rst = "Intro\n=====\n\nUsage\n-----\n"
    headings = @generic.send(:extract_rst_headings, rst, "Something Else")
    assert_equal [ "Intro", "Usage" ], headings
  end

  test "extract_rst_headings strips RST role markup" do
    rst = "Title\n=====\n\n:mod:`jsonschema`\n=================\n"
    headings = @generic.send(:extract_rst_headings, rst, "Title")
    assert_equal [ "jsonschema" ], headings
  end

  test "extract_rst_headings handles same-char sections" do
    rst = "Title\n=====\n\nSection One\n===========\n\nSection Two\n===========\n"
    headings = @generic.send(:extract_rst_headings, rst, "Title")
    assert_equal [ "Section One", "Section Two" ], headings
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

    content, _title = @generic.send(:convert_content, notebook, ".ipynb")
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

    content, _title = @generic.send(:convert_content, notebook, ".ipynb")
    assert_equal "", content.strip
  end

  test "convert_content handles invalid ipynb JSON" do
    content, _title = @generic.send(:convert_content, "not json at all", ".ipynb")
    assert_nil content
  end


  # --- Strip frontmatter ---

  test "strip_frontmatter removes YAML frontmatter" do
    content = "---\ntitle: Test\n---\n\n# Hello"
    result = @generic.send(:strip_frontmatter, content)
    assert_equal "# Hello", result
  end

  test "strip_frontmatter leaves non-frontmatter content alone" do
    content = "# Hello\n\nWorld"
    result = @generic.send(:strip_frontmatter, content)
    assert_equal content, result
  end

  # --- Build file URL ---

  test "builds GitHub file URL" do
    url = @github.send(:build_file_url, "https://github.com/rails/rails", "docs/guide.md", "main")
    assert_equal "https://github.com/rails/rails/blob/main/docs/guide.md", url
  end

  test "builds GitLab file URL" do
    url = @gitlab.send(:build_file_url, "https://gitlab.com/group/project", "docs/guide.md", "main")
    assert_equal "https://gitlab.com/group/project/-/blob/main/docs/guide.md", url
  end

  test "builds Bitbucket file URL" do
    url = @bitbucket.send(:build_file_url, "https://bitbucket.org/owner/repo", "docs/guide.md", "main")
    assert_equal "https://bitbucket.org/owner/repo/src/main/docs/guide.md", url
  end

  # --- Result building ---

  test "build_result creates correct CrawlResult" do
    pages = [
      { page_uid: "readme", path: "README.md", title: "Readme", url: "https://example.com", content: "# Hi", headings: [] }
    ]
    result = @github.send(:build_result, "owner", "my-lib", "https://github.com/owner/my-lib", pages, "1.0.0")

    assert_instance_of CrawlResult, result
    assert_equal "owner", result.namespace
    assert_equal "my-lib", result.name
    assert_equal "My Lib", result.display_name
    assert_equal "1.0.0", result.version
    assert_equal 1, result.pages.size
    assert_includes result.aliases, "my-lib"
    assert_includes result.aliases, "mylib"
  end

  test "build_result prefers owner naming for generic docs repos" do
    pages = [
      { page_uid: "readme", path: "README.md", title: "Readme", url: "https://example.com", content: "# Hi", headings: [] }
    ]
    result = @github.send(:build_result, "laravel", "docs", "https://github.com/laravel/docs", pages, "12.x")

    assert_equal "laravel", result.namespace
    assert_equal "docs", result.name
    assert_equal "Laravel", result.display_name
    assert_equal "laravel", result.aliases.first
    assert_includes result.aliases, "docs"
  end

  # --- Fetcher dispatch ---

  test "DocsFetcher.for returns GitHub instance for github source_type" do
    fetcher = DocsFetcher.for("github")
    assert_instance_of DocsFetcher::Git::Github, fetcher
  end

  test "DocsFetcher.for returns GitLab instance for gitlab source_type" do
    fetcher = DocsFetcher.for("gitlab")
    assert_instance_of DocsFetcher::Git::Gitlab, fetcher
  end

  test "DocsFetcher.for returns Bitbucket instance for bitbucket source_type" do
    fetcher = DocsFetcher.for("bitbucket")
    assert_instance_of DocsFetcher::Git::Bitbucket, fetcher
  end

  test "DocsFetcher.for returns Git base for git source_type" do
    fetcher = DocsFetcher.for("git")
    assert_instance_of DocsFetcher::Git, fetcher
  end

  # --- Default exclude: directory prefixes ---

  test "discover_doc_files skips default excluded directories" do
    Dir.mktmpdir("test-git-") do |tmpdir|
      # Create files in excluded dirs
      %w[vendor/lib.md node_modules/readme.md test/helper.md archive/old.md
         build/output.md .github/ci.md demo/quickstart.md i18n/fr.md].each do |rel|
        path = File.join(tmpdir, rel)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "# Content")
      end
      # Create file in non-excluded dir
      FileUtils.mkdir_p(File.join(tmpdir, "docs"))
      File.write(File.join(tmpdir, "docs", "guide.md"), "# Guide")
      File.write(File.join(tmpdir, "README.md"), "# Hello")

      candidates = @generic.send(:discover_doc_files, tmpdir)
      rel_paths = candidates.map { |c| c.sub("#{tmpdir}/", "") }

      assert_includes rel_paths, "docs/guide.md"
      assert_includes rel_paths, "README.md"
      assert_not rel_paths.any? { |p| p.start_with?("vendor/") }
      assert_not rel_paths.any? { |p| p.start_with?("node_modules/") }
      assert_not rel_paths.any? { |p| p.start_with?("test/") }
      assert_not rel_paths.any? { |p| p.start_with?("archive/") }
      assert_not rel_paths.any? { |p| p.start_with?("build/") }
      assert_not rel_paths.any? { |p| p.start_with?(".github/") }
      assert_not rel_paths.any? { |p| p.start_with?("demo/") }
      assert_not rel_paths.any? { |p| p.start_with?("i18n/") }
    end
  end

  # --- Default exclude: basenames ---

  test "discover_doc_files skips default excluded basenames" do
    Dir.mktmpdir("test-git-") do |tmpdir|
      File.write(File.join(tmpdir, "CHANGELOG.md"), "# Changelog")
      File.write(File.join(tmpdir, "LICENSE.md"), "MIT")
      File.write(File.join(tmpdir, "CODE_OF_CONDUCT.md"), "Be nice")
      File.write(File.join(tmpdir, "CONTRIBUTING.md"), "How to contribute")
      File.write(File.join(tmpdir, "SECURITY.md"), "Report bugs")
      File.write(File.join(tmpdir, "README.md"), "# Real docs")

      candidates = @generic.send(:discover_doc_files, tmpdir)
      basenames = candidates.map { |c| File.basename(c) }

      assert_includes basenames, "README.md"
      assert_not_includes basenames, "CHANGELOG.md"
      assert_not_includes basenames, "LICENSE.md"
      assert_not_includes basenames, "CODE_OF_CONDUCT.md"
      assert_not_includes basenames, "CONTRIBUTING.md"
      assert_not_includes basenames, "SECURITY.md"
    end
  end

  # --- Include prefixes override excludes ---

  test "discover_doc_files respects include prefixes overriding excludes" do
    Dir.mktmpdir("test-git-") do |tmpdir|
      # test/ is excluded by default, but include should override
      FileUtils.mkdir_p(File.join(tmpdir, "test", "docs"))
      File.write(File.join(tmpdir, "test", "docs", "guide.md"), "# Test Guide")
      FileUtils.mkdir_p(File.join(tmpdir, "examples"))
      File.write(File.join(tmpdir, "examples", "tutorial.md"), "# Tutorial")

      # Set crawl_rules with include_prefixes
      @generic.instance_variable_set(:@crawl_rules, {
        "git_include_prefixes" => [ "test/docs", "examples" ]
      })

      candidates = @generic.send(:discover_doc_files, tmpdir)
      rel_paths = candidates.map { |c| c.sub("#{tmpdir}/", "") }

      assert_includes rel_paths, "test/docs/guide.md"
      assert_includes rel_paths, "examples/tutorial.md"
    end
  end

  # --- Library-specific extra excludes ---

  test "discover_doc_files applies library-specific exclude prefixes" do
    Dir.mktmpdir("test-git-") do |tmpdir|
      FileUtils.mkdir_p(File.join(tmpdir, "internal"))
      File.write(File.join(tmpdir, "internal", "notes.md"), "# Internal notes")
      FileUtils.mkdir_p(File.join(tmpdir, "docs"))
      File.write(File.join(tmpdir, "docs", "guide.md"), "# Guide")

      @generic.instance_variable_set(:@crawl_rules, {
        "git_exclude_prefixes" => [ "internal" ]
      })

      candidates = @generic.send(:discover_doc_files, tmpdir)
      rel_paths = candidates.map { |c| c.sub("#{tmpdir}/", "") }

      assert_includes rel_paths, "docs/guide.md"
      assert_not rel_paths.any? { |p| p.start_with?("internal/") }
    end
  end

  test "discover_doc_files applies library-specific exclude basenames" do
    Dir.mktmpdir("test-git-") do |tmpdir|
      File.write(File.join(tmpdir, "README.md"), "# Hello")
      File.write(File.join(tmpdir, "MIGRATION.md"), "# Migration notes")

      @generic.instance_variable_set(:@crawl_rules, {
        "git_exclude_basenames" => [ "MIGRATION.md" ]
      })

      candidates = @generic.send(:discover_doc_files, tmpdir)
      basenames = candidates.map { |c| File.basename(c) }

      assert_includes basenames, "README.md"
      assert_not_includes basenames, "MIGRATION.md"
    end
  end

  # --- First crawl (no library_id) uses defaults only ---

  test "load_crawl_rules returns empty hash without library_id" do
    crawl_request = Struct.new(:library_id, :library).new(nil, nil)
    result = @generic.send(:load_crawl_rules, crawl_request)
    assert_equal({}, result)
  end

  # --- Source type detection ---

  test "detect_source_type returns github for github.com URLs" do
    assert_equal "github", DocsFetcher.detect_source_type("https://github.com/rails/rails")
  end

  test "detect_source_type returns gitlab for gitlab.com URLs" do
    assert_equal "gitlab", DocsFetcher.detect_source_type("https://gitlab.com/group/project")
  end

  test "detect_source_type returns bitbucket for bitbucket.org URLs" do
    assert_equal "bitbucket", DocsFetcher.detect_source_type("https://bitbucket.org/team/repo")
  end

  test "detect_source_type returns gitlab for self-hosted gitlab" do
    assert_equal "gitlab", DocsFetcher.detect_source_type("https://gitlab.mycompany.com/team/project")
  end

  # --- New exclude patterns ---

  test "discover_doc_files skips .changeset and AI config files" do
    Dir.mktmpdir("test-git-") do |tmpdir|
      FileUtils.mkdir_p(File.join(tmpdir, ".changeset"))
      File.write(File.join(tmpdir, ".changeset", "README.md"), "# Changeset")
      File.write(File.join(tmpdir, "CLAUDE.md"), "# Claude config")
      File.write(File.join(tmpdir, "AGENTS.md"), "# Agents config")
      File.write(File.join(tmpdir, "GEMINI.md"), "# Gemini config")
      File.write(File.join(tmpdir, "README.md"), "# Real docs")

      candidates = @generic.send(:discover_doc_files, tmpdir)
      rel_paths = candidates.map { |c| c.sub("#{tmpdir}/", "") }
      basenames = candidates.map { |c| File.basename(c) }

      assert_includes rel_paths, "README.md"
      assert_not rel_paths.any? { |p| p.start_with?(".changeset/") }
      assert_not_includes basenames, "CLAUDE.md"
      assert_not_includes basenames, "AGENTS.md"
      assert_not_includes basenames, "GEMINI.md"
    end
  end

  test "discover_doc_files skips i18n-guides directory" do
    Dir.mktmpdir("test-git-") do |tmpdir|
      FileUtils.mkdir_p(File.join(tmpdir, "i18n-guides"))
      File.write(File.join(tmpdir, "i18n-guides", "français.md"), "# Guide français")
      File.write(File.join(tmpdir, "README.md"), "# Real docs")

      candidates = @generic.send(:discover_doc_files, tmpdir)
      rel_paths = candidates.map { |c| c.sub("#{tmpdir}/", "") }

      assert_includes rel_paths, "README.md"
      assert_not rel_paths.any? { |p| p.start_with?("i18n-guides/") }
    end
  end
end
