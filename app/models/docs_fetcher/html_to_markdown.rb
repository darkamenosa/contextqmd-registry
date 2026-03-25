# frozen_string_literal: true

require "cgi"
require "nokogiri"
require "reverse_markdown"
require "uri"

module ReverseMarkdown
  module Converters
    class PreWithCodeLanguage < Pre
      private

        def language(node)
          super || language_from_code_class(node)
        end

        def language_from_code_class(node)
          code = node.at_css("code")
          return unless code

          code["class"].to_s.split.each do |class_name|
            match = class_name.match(/\A(?:language|lang)-([a-z0-9_+-]+)\z/i)
            return match[1].downcase if match
          end

          nil
        end
    end

    register :pre, PreWithCodeLanguage.new
  end
end

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

        normalize_code_blocks
        normalize_text_nodes
        normalize_links
        strip_decorative_images
        strip_empty_links
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
          .gsub("\u00A0", " ")
          .gsub(/&nbsp;/i, " ")
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

      def normalize_text_nodes
        @doc.xpath("//text()").each do |node|
          node.content = node.text.tr("\u00A0", " ")
        end
      end

      def normalize_code_blocks
        unwrap_nested_pre_blocks

        @doc.css("pre code").each do |code|
          text = code.text.to_s.tr("\u00A0", " ")
          code.children.remove
          code.content = text
          code.remove_attribute("style")
          code.parent&.remove_attribute("style")
        end
      end

      def unwrap_nested_pre_blocks
        @doc.css("pre").each do |outer_pre|
          inner_pre = outer_pre.element_children.first
          next unless inner_pre&.name == "pre"
          next unless outer_pre.children.all? { |child| child == inner_pre || child.text? && child.text.strip.empty? }

          outer_pre.replace(inner_pre)
        end
      end

      def normalize_links
        @doc.css("a[href]").each do |link|
          href = normalized_href(link["href"])

          if href.present?
            link["href"] = href
          else
            link.remove_attribute("href")
          end
        end
      end

      def normalized_href(href)
        href = href.to_s.strip
        return if href.empty?

        uri = parse_uri(href)
        return href if uri.nil?

        unwrapped_uri = unwrap_facebook_redirect(uri)
        stripped_uri = strip_tracking_query_params(unwrapped_uri)
        stripped_uri.to_s
      end

      def unwrap_facebook_redirect(uri)
        if uri.host&.end_with?("facebook.com") && uri.path == "/l.php"
          query = URI.decode_www_form(uri.query.to_s).to_h

          if query["u"].present?
            redirected_uri = parse_uri(CGI.unescape(query["u"]))
            return redirected_uri if redirected_uri
          end
        end

        uri
      end

      def strip_tracking_query_params(uri)
        query_params = URI.decode_www_form(uri.query.to_s)
        filtered_params = query_params.reject do |key, _value|
          key.start_with?("utm_", "__") || %w[ref source campaign fbclid gclid].include?(key)
        end

        if filtered_params.any?
          uri.query = URI.encode_www_form(filtered_params)
        else
          uri.query = nil
        end

        uri
      end

      def strip_decorative_images
        @doc.css("img").each do |image|
          image.remove if decorative_image?(image)
        end
      end

      def decorative_image?(image)
        src = image["src"].to_s
        alt = image["alt"].to_s.strip

        alt.empty? || src.start_with?("data:")
      end

      def strip_empty_links
        @doc.css("a").each do |link|
          link.remove if link.text.strip.empty?
        end
      end

      def parse_uri(href)
        URI.parse(href)
      rescue URI::InvalidURIError
        nil
      end
  end
end
