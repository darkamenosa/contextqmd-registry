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

    assert_equal "docs", metadata[:namespace]
    assert_equal "docs-llms-txt", metadata[:name]
    assert_equal "My Great Lib (llms.txt)", metadata[:display_name]
    assert_includes metadata[:aliases], "docs"
  end

  test "extracts metadata with llms-full.txt URL" do
    uri = URI.parse("https://react.dev/llms-full.txt")
    content = "# React Documentation\n\nContent."

    metadata = @fetcher.send(:extract_metadata, uri, content)

    assert_equal "react", metadata[:namespace]
    assert_equal "react-llms-full-txt", metadata[:name]
    assert_equal "React Documentation (llms.txt)", metadata[:display_name]
  end

  test "falls back to namespace for display name when no H1" do
    uri = URI.parse("https://tailwindcss.com/llms.txt")
    content = "Just plain text, no heading."

    metadata = @fetcher.send(:extract_metadata, uri, content)

    assert_equal "Tailwindcss (llms.txt)", metadata[:display_name]
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
    fetcher.define_singleton_method(:http_get) { |*_args, **_kw| content }

    result = fetcher.fetch("https://example.com/llms.txt")

    assert_instance_of DocsFetcher::Result, result
    assert_equal "example", result.namespace
    assert_equal "example-llms-txt", result.name
    assert_equal 3, result.pages.size
    assert_equal "https://example.com", result.homepage_url
  end

  test "fetch uses fallback when no sections can be split" do
    content = "Just a block of plain text.\nNo headings at all."

    fetcher = DocsFetcher::LlmsTxt.new
    fetcher.define_singleton_method(:http_get) { |*_args, **_kw| content }

    result = fetcher.fetch("https://example.com/llms.txt")

    assert_instance_of DocsFetcher::Result, result
    assert_equal 1, result.pages.size
    assert_equal "llms-txt", result.pages.first[:page_uid]
  end

  test "fetch raises when HTTP returns nil" do
    fetcher = DocsFetcher::LlmsTxt.new
    fetcher.define_singleton_method(:http_get) { |*_args, **_kw| nil }

    assert_raises(RuntimeError) do
      fetcher.fetch("https://example.com/llms.txt")
    end
  end
end
