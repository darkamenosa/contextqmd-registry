# frozen_string_literal: true

require "nokogiri"
require "reverse_markdown"

module DocsFetcher
  # Converts an HTML page to clean Markdown.
  # Extracts the main content area, strips boilerplate (nav, footer, sidebar),
  # and converts the remainder to Markdown via reverse_markdown.
  class HtmlToMarkdown
    # CSS selectors for the main content area, tried in order of specificity.
    CONTENT_SELECTORS = [
      "article",
      "[role='main']",
      "main",
      ".docs-content",
      ".markdown-body",
      ".prose",
      ".content",
      "#content",
      "#main-content",
      ".documentation",
      ".doc-content",
      ".guide-body"
    ].freeze

    # Elements that are always noise.
    STRIP_SELECTORS = %w[
      nav header footer aside
      .sidebar .nav .navbar .toc .table-of-contents
      .breadcrumb .breadcrumbs .pagination
      .edit-link .edit-page .github-link
      .newsletter .banner .cookie-banner
      script style noscript iframe
      [role='navigation'] [role='banner'] [role='contentinfo']
    ].freeze

    # Convert a full HTML document string to clean Markdown.
    # Returns { title:, content:, headings: }.
    def self.convert(html)
      new(html).convert
    end

    def initialize(html)
      @doc = Nokogiri::HTML(html)
    end

    def convert
      strip_noise
      node = find_content_node
      return empty_result if node.nil? || node.text.strip.empty?

      markdown = to_markdown(node)
      markdown = clean_markdown(markdown)
      return empty_result if markdown.strip.empty?

      {
        title: extract_title,
        content: markdown,
        headings: extract_headings(markdown)
      }
    end

    private

      def strip_noise
        STRIP_SELECTORS.each do |sel|
          @doc.css(sel).each(&:remove)
        end
      end

      def find_content_node
        CONTENT_SELECTORS.each do |sel|
          node = @doc.at_css(sel)
          return node if node && node.text.strip.length > 100
        end
        # Fallback to body
        @doc.at_css("body")
      end

      def to_markdown(node)
        ReverseMarkdown.convert(
          node.to_html,
          unknown_tags: :bypass,
          github_flavored: true
        )
      end

      def clean_markdown(md)
        md
          .gsub(/\n{3,}/, "\n\n")           # collapse excessive blank lines
          .gsub(/^\s+$/, "")                 # strip whitespace-only lines
          .gsub(/\[([^\]]+)\]\(\s*\)/, '\1') # remove links with empty href
          .strip
      end

      def extract_title
        # Prefer <h1> inside content, then <title>
        h1 = @doc.at_css("h1")
        return h1.text.strip if h1 && h1.text.strip.length > 2

        title_tag = @doc.at_css("title")
        return title_tag.text.strip.split(/\s*[|–—-]\s*/).first&.strip if title_tag

        nil
      end

      def extract_headings(markdown)
        markdown.scan(/^\#{2,4}\s+(.+)$/).flatten.map(&:strip)
      end

      def empty_result
        { title: nil, content: "", headings: [] }
      end
  end
end
