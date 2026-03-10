# frozen_string_literal: true

require "test_helper"

class DocsFetcher::LlmsTxtTest < ActiveSupport::TestCase
  setup do
    @fetcher = DocsFetcher::LlmsTxt.new
  end

  # --- Section splitting ---

  test "splits content on H2 headings when there are multiple H2s" do
    content = <<~MD
      # My Library

      Overview paragraph.

      ## Installation

      Install with npm.

      ## Usage

      Use it like this.

      ## API Reference

      All the functions.
    MD

    pages = @fetcher.send(:split_into_sections, content, "https://example.com/llms.txt")
    titles = pages.map { |p| p[:title] }

    assert_equal 4, pages.size
    assert_includes titles, "Overview"
    assert_includes titles, "Installation"
    assert_includes titles, "Usage"
    assert_includes titles, "API Reference"
  end

  test "falls back to H1 splitting when fewer than 2 H2s" do
    content = <<~MD
      # Getting Started

      Some intro text.

      # Advanced Usage

      Advanced things here.

      # API

      Function reference.
    MD

    pages = @fetcher.send(:split_into_sections, content, "https://example.com/llms.txt")
    titles = pages.map { |p| p[:title] }

    assert_equal 3, pages.size
    assert_includes titles, "Getting Started"
    assert_includes titles, "Advanced Usage"
    assert_includes titles, "API"
  end

  test "returns empty array when no splittable headings found" do
    content = "Just plain text without any headings.\nMore text here."
    pages = @fetcher.send(:split_into_sections, content, "https://example.com/llms.txt")
    assert_empty pages
  end

  test "ignores H3 headings for splitting" do
    content = <<~MD
      # Title

      Overview.

      ### Sub Section One

      Content one.

      ### Sub Section Two

      Content two.
    MD

    # Only 1 H1, 0 H2s -> detect_split_level returns nil
    pages = @fetcher.send(:split_into_sections, content, "https://example.com/llms.txt")
    assert_empty pages
  end

  # --- Metadata extraction ---

  test "extracts metadata from URL and content" do
    uri = URI.parse("https://docs.example.com/llms.txt")
    content = "# My Great Lib\n\nSome content."

    metadata = @fetcher.send(:extract_metadata, uri, content)

    assert_equal "example", metadata[:namespace]
    assert_equal "example", metadata[:name]
    assert_equal "My Great Lib", metadata[:display_name]
    assert_includes metadata[:aliases], "example"
  end

  test "extracts metadata with llms-full.txt URL" do
    uri = URI.parse("https://react.dev/llms-full.txt")
    content = "# React Documentation\n\nContent."

    metadata = @fetcher.send(:extract_metadata, uri, content)

    assert_equal "react", metadata[:namespace]
    assert_equal "react", metadata[:name]
    assert_equal "React Documentation", metadata[:display_name]
  end

  test "falls back to namespace for display name when no H1" do
    uri = URI.parse("https://tailwindcss.com/llms.txt")
    content = "Just plain text, no heading."

    metadata = @fetcher.send(:extract_metadata, uri, content)

    assert_equal "Tailwindcss", metadata[:display_name]
  end

  test "strips www prefix from host for namespace" do
    uri = URI.parse("https://www.example.com/llms.txt")
    content = "# Example\n\nContent."

    metadata = @fetcher.send(:extract_metadata, uri, content)

    assert_equal "example", metadata[:namespace]
  end

  # --- Fallback single page ---

  test "fallback_single_page returns a single page hash" do
    content = "## Heading One\n\nContent.\n\n## Heading Two\n\nMore content."
    url = "https://example.com/llms.txt"
    display_name = "Example (llms.txt)"

    page = @fetcher.send(:fallback_single_page, content, url, display_name)

    assert_equal "llms-txt", page[:page_uid]
    assert_equal "llms.txt", page[:path]
    assert_equal display_name, page[:title]
    assert_equal url, page[:url]
    assert_equal content, page[:content]
    assert_includes page[:headings], "Heading One"
    assert_includes page[:headings], "Heading Two"
  end

  # --- Slug generation ---

  test "make_slug generates a slug from title" do
    slug_counts = Hash.new(0)
    slug = @fetcher.send(:make_slug, "Getting Started with Next.js", slug_counts)
    assert_equal "getting-started-with-nextjs", slug
  end

  test "make_slug deduplicates slugs" do
    slug_counts = Hash.new(0)
    slug1 = @fetcher.send(:make_slug, "Overview", slug_counts)
    slug2 = @fetcher.send(:make_slug, "Overview", slug_counts)

    assert_equal "overview", slug1
    assert_equal "overview-2", slug2
  end

  test "make_slug handles empty title" do
    slug_counts = Hash.new(0)
    slug = @fetcher.send(:make_slug, "", slug_counts)
    assert_equal "section", slug
  end

  test "make_slug strips special characters" do
    slug_counts = Hash.new(0)
    slug = @fetcher.send(:make_slug, "What's New? (v2.0)", slug_counts)
    assert_equal "whats-new-v20", slug
  end

  # --- Sub-headings extraction ---

  test "extract_sub_headings finds headings deeper than split level" do
    content = <<~MD
      ## Main Section

      Content here.

      ### Sub Section

      More content.

      #### Deep Section

      Even more.
    MD

    headings = @fetcher.send(:extract_sub_headings, content, 2)
    assert_includes headings, "Sub Section"
    assert_includes headings, "Deep Section"
    assert_equal 2, headings.size
  end

  # --- Detect split level ---

  test "detect_split_level returns 2 for content with 2+ H2s" do
    content = "## First\n\nText\n\n## Second\n\nText"
    assert_equal 2, @fetcher.send(:detect_split_level, content)
  end

  test "detect_split_level returns 1 for content with 2+ H1s but fewer than 2 H2s" do
    content = "# First\n\nText\n\n# Second\n\nText"
    assert_equal 1, @fetcher.send(:detect_split_level, content)
  end

  test "detect_split_level returns nil for insufficient headings" do
    content = "# Only one heading\n\nJust text."
    assert_nil @fetcher.send(:detect_split_level, content)
  end

  # --- Index detection ---

  test "index_style? returns true for content with many doc links" do
    content = <<~MD
      # Inertia Rails

      > Build modern SPAs with Rails.

      ## Table of Contents

      - [Introduction](/guide.md)
      - [Server-side setup](/guide/server-side-setup.md)
      - [Client-side setup](/guide/client-side-setup.md)
      - [Pages](/guide/pages.md)
      - [Responses](/guide/responses.md)
      - [Redirects](/guide/redirects.md)
      - [Forms](/guide/forms.md)
      - [Validation](/guide/validation.md)
      - [Shared data](/guide/shared-data.md)
      - [Testing](/guide/testing.md)
    MD

    assert @fetcher.send(:index_style?, content)
  end

  test "index_style? returns false for content-rich file" do
    content = <<~MD
      # My Library

      This is a full documentation file with lots of content.

      ## Installation

      Run `npm install my-library` to install the package. Then import it
      in your application and configure the settings as described below.
      Make sure you have Node.js 18+ installed.

      ## Usage

      Here's how you use the library in your code. First create an instance,
      then call the methods you need. The API is designed to be intuitive
      and easy to learn.

      ## API Reference

      The main class exposes several methods for working with data.
      Each method returns a promise that resolves with the result.
    MD

    assert_not @fetcher.send(:index_style?, content)
  end

  test "index_style? returns false for fewer than 5 links" do
    content = <<~MD
      # Small project

      - [README](/README.md)
      - [Guide](/guide.md)

      Lots of prose content goes here to fill the page.
    MD

    assert_not @fetcher.send(:index_style?, content)
  end

  # --- Link extraction ---

  test "extract_doc_links finds markdown links to .md files" do
    content = <<~MD
      - [Introduction](/guide.md)
      - [Setup](/guide/setup.md)
      - [Not a doc](https://example.com/page)
      - [Also a doc](/reference/api.mdx)
    MD

    links = @fetcher.send(:extract_doc_links, content)
    paths = links.map { |l| l[:path] }

    assert_includes paths, "/guide.md"
    assert_includes paths, "/guide/setup.md"
    assert_includes paths, "/reference/api.mdx"
    assert_not_includes paths, "https://example.com/page"
  end

  test "extract_doc_links deduplicates by path" do
    content = <<~MD
      - [Intro](/guide.md)
      - [Introduction](/guide.md)
    MD

    links = @fetcher.send(:extract_doc_links, content)
    assert_equal 1, links.size
  end

  test "extract_doc_links finds absolute URLs ending in .md" do
    content = <<~MD
      - [Quick Start](https://react.dev/learn.md)
      - [Tutorial](https://react.dev/learn/tutorial-tic-tac-toe.md)
      - [Not a doc](https://react.dev/blog)
    MD

    links = @fetcher.send(:extract_doc_links, content)
    paths = links.map { |l| l[:path] }

    assert_includes paths, "https://react.dev/learn.md"
    assert_includes paths, "https://react.dev/learn/tutorial-tic-tac-toe.md"
    assert_not_includes paths, "https://react.dev/blog"
  end

  # --- Frontmatter stripping ---

  test "strip_frontmatter removes YAML frontmatter" do
    content = "---\nurl: /guide/pages.md\n---\n# Pages\n\nContent here."
    stripped = @fetcher.send(:strip_frontmatter, content)

    assert_equal "# Pages\n\nContent here.", stripped
  end

  test "strip_frontmatter returns content unchanged when no frontmatter" do
    content = "# No Frontmatter\n\nJust content."
    stripped = @fetcher.send(:strip_frontmatter, content)

    assert_equal content, stripped
  end

  test "extract_title_from_content finds title in frontmatter" do
    content = "---\ntitle: My Page Title\n---\n# Different Heading\n\nContent."
    title = @fetcher.send(:extract_title_from_content, content)

    assert_equal "My Page Title", title
  end

  test "extract_title_from_content finds ATX heading after frontmatter" do
    content = "---\nurl: /guide.md\n---\n# Getting Started\n\nContent."
    title = @fetcher.send(:extract_title_from_content, content)

    assert_equal "Getting Started", title
  end

  # --- Link resolution ---

  test "resolve_link resolves relative paths against base URI" do
    base = URI.parse("https://inertia-rails.dev/llms.txt")
    resolved = @fetcher.send(:resolve_link, base, "/guide/pages.md")

    assert_equal "https://inertia-rails.dev/guide/pages.md", resolved.to_s
  end

  test "resolve_link returns absolute URLs as-is" do
    base = URI.parse("https://inertia-rails.dev/llms.txt")
    resolved = @fetcher.send(:resolve_link, base, "https://other.dev/docs.md")

    assert_equal "https://other.dev/docs.md", resolved.to_s
  end

  # --- Full fetch with stubbed HTTP ---

  test "fetch returns a Result with pages from H2 sections" do
    content = <<~MD
      # My Library

      Overview.

      ## Installation

      Install steps.

      ## Configuration

      Config details.
    MD

    fetcher = DocsFetcher::LlmsTxt.new
    # Stub http_get to return nil for llms-full.txt, content for llms.txt
    call_count = 0
    fetcher.define_singleton_method(:http_get) do |uri, **_kw|
      call_count += 1
      call_count == 1 ? nil : content # first call is llms-full.txt (nil), second is llms.txt
    end

    result = fetcher.fetch(Struct.new(:url).new("https://example.com/llms.txt"))

    assert_instance_of CrawlResult, result
    assert_equal "example", result.namespace
    assert_equal "example", result.name
    assert_equal 3, result.pages.size
    assert_equal "https://example.com", result.homepage_url
  end

  test "fetch prefers llms-full.txt when available" do
    full_content = <<~MD
      # My Library Full

      All the docs are here.

      ## Getting Started

      Full getting started guide with lots of content here.

      ## API Reference

      Complete API reference documentation.
    MD

    fetcher = DocsFetcher::LlmsTxt.new
    fetcher.define_singleton_method(:http_get) { |*_args, **_kw| full_content }

    result = fetcher.fetch(Struct.new(:url).new("https://example.com/llms.txt"))

    assert_instance_of CrawlResult, result
    assert_equal "example", result.name
    assert_equal 3, result.pages.size
  end

  test "fetch follows links for index-style llms.txt" do
    index_content = <<~MD
      # My Framework

      > Build things fast.

      - [Introduction](/guide.md)
      - [Setup](/guide/setup.md)
      - [Pages](/guide/pages.md)
      - [Forms](/guide/forms.md)
      - [Validation](/guide/validation.md)
      - [Testing](/guide/testing.md)
      - [Advanced](/guide/advanced.md)
    MD

    page_content = "# Introduction\n\nWelcome to the framework.\n\n## Overview\n\nThis is great."

    fetcher = DocsFetcher::LlmsTxt.new
    call_count = 0
    fetcher.define_singleton_method(:http_get) do |uri, **_kw|
      call_count += 1
      if call_count == 1
        nil # llms-full.txt not found
      elsif call_count == 2
        index_content # llms.txt itself
      else
        page_content # each linked page
      end
    end

    result = fetcher.fetch(Struct.new(:url).new("https://example.com/llms.txt"))

    assert_instance_of CrawlResult, result
    assert_equal 7, result.pages.size
    assert_equal "Introduction", result.pages.first[:title]
    assert_includes result.pages.first[:headings], "Overview"
  end

  test "fetch uses fallback when no sections can be split" do
    content = "Just a block of plain text.\nNo headings at all."

    fetcher = DocsFetcher::LlmsTxt.new
    call_count = 0
    fetcher.define_singleton_method(:http_get) do |*_args, **_kw|
      call_count += 1
      call_count == 1 ? nil : content
    end

    result = fetcher.fetch(Struct.new(:url).new("https://example.com/llms.txt"))

    assert_instance_of CrawlResult, result
    assert_equal 1, result.pages.size
    assert_equal "llms-txt", result.pages.first[:page_uid]
  end

  test "fetch raises when HTTP returns nil" do
    fetcher = DocsFetcher::LlmsTxt.new
    fetcher.define_singleton_method(:http_get) { |*_args, **_kw| nil }

    assert_raises(DocsFetcher::TransientFetchError) do
      fetcher.fetch(Struct.new(:url).new("https://example.com/llms.txt"))
    end
  end

  # --- llms-small.txt support ---

  test "fetch uses llms-small.txt directly without trying llms-full.txt" do
    content = <<~MD
      # My Library (Small)

      Condensed overview.

      ## Quick Start

      Install and run.

      ## API

      Main functions.
    MD

    fetcher = DocsFetcher::LlmsTxt.new
    urls_fetched = []
    fetcher.define_singleton_method(:http_get) do |uri, **_kw|
      urls_fetched << uri.to_s
      content
    end

    result = fetcher.fetch(Struct.new(:url).new("https://example.com/llms-small.txt"))

    assert_instance_of CrawlResult, result
    # Should NOT have tried llms-full.txt
    assert_not urls_fetched.any? { |u| u.include?("llms-full.txt") },
      "Should not attempt llms-full.txt when fetching llms-small.txt"
    # Should have fetched only the llms-small.txt URL
    assert_equal 1, urls_fetched.size
    assert_includes urls_fetched.first, "llms-small.txt"
  end

  test "fetch parses llms-small.txt content the same as llms.txt" do
    content = <<~MD
      # Condensed Docs

      Overview.

      ## Installation

      Install steps.

      ## Usage

      Usage info.
    MD

    fetcher = DocsFetcher::LlmsTxt.new
    fetcher.define_singleton_method(:http_get) { |*_args, **_kw| content }

    result = fetcher.fetch(Struct.new(:url).new("https://example.com/llms-small.txt"))

    assert_instance_of CrawlResult, result
    assert_equal 3, result.pages.size
    titles = result.pages.map { |p| p[:title] }
    assert_includes titles, "Installation"
    assert_includes titles, "Usage"
  end

  test "fetch strips llms-small.txt from homepage_url" do
    content = <<~MD
      # Lib

      Overview.

      ## Section A

      Content A.

      ## Section B

      Content B.
    MD

    fetcher = DocsFetcher::LlmsTxt.new
    fetcher.define_singleton_method(:http_get) { |*_args, **_kw| content }

    result = fetcher.fetch(Struct.new(:url).new("https://example.com/llms-small.txt"))

    assert_equal "https://example.com", result.homepage_url
  end
end
