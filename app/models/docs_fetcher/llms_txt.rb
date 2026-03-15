# frozen_string_literal: true

module DocsFetcher
  # Fetches documentation from an llms.txt or llms-full.txt file.
  #
  # Handles two formats:
  # 1. **Full content** (llms-full.txt or inline llms.txt): A single markdown file
  #    with all documentation content under headings. Split into pages by H2/H1.
  # 2. **Index/TOC** (llms.txt with links): A navigation file listing markdown links
  #    like `[Title](/guide/page.md)`. Each linked page is fetched individually.
  #
  # Strategy:
  # - If URL is llms.txt, first try llms-full.txt (has all content inline)
  # - If that fails or URL is explicit, fetch the given URL
  # - Detect whether fetched content is an index (many links, little prose)
  # - If index: follow links to fetch each page's content
  # - If full content: split by headings into pages
  class LlmsTxt
    include HttpFetching

    MAX_SIZE = 50_000_000       # 50 MB per fetched file
    MAX_TOTAL_BYTES = 20_000_000 # 20 MB total content budget

    def fetch(crawl_request, on_progress: nil)
      url = crawl_request.url
      uri = URI.parse(url.strip)
      content = nil
      used_full = false
      metadata_uri = uri
      metadata_content = nil

      # Try llms-full.txt first if URL points to llms.txt (but NOT llms-small.txt)
      if uri.path.end_with?("/llms.txt")
        on_progress&.call("Trying llms-full.txt")
        full_uri = uri.dup
        full_uri.path = uri.path.sub(/\/llms\.txt\z/, "/llms-full.txt")
        full_content = http_get(full_uri)
        if full_content && full_content.strip.length > 100
          content = full_content
          metadata_content = http_get(uri)
          uri = full_uri
          used_full = true
        end
      end
      # llms-small.txt and llms-full.txt are used directly — no upgrade/downgrade

      on_progress&.call("Fetching #{File.basename(uri.path)}")
      content ||= http_get(uri, raise_on_error: true)
      raise DocsFetcher::TransientFetchError, "Failed to fetch #{url}" unless content

      metadata = extract_metadata(metadata_uri, metadata_content.presence || content)
      section_base_url = canonical_llms_source_url(url)

      # Decide strategy: index with links or inline content?
      if !used_full && index_style?(content)
        on_progress&.call("Following linked pages")
        pages, complete = fetch_linked_pages(uri, content, on_progress: on_progress)
      else
        on_progress&.call("Splitting into sections")
        pages = split_into_sections(content, section_base_url)
        complete = true # section splitting processes all content, never truncated
      end

      if pages.empty?
        pages = [ fallback_single_page(content, section_base_url, metadata[:display_name]) ]
      end

      CrawlResult.new(
        slug: metadata[:slug],
        namespace: metadata[:namespace],
        name: metadata[:name],
        display_name: metadata[:display_name],
        homepage_url: url.sub(%r{/llms(?:-full|-small)?\.txt$}, ""),
        aliases: metadata[:aliases],
        version: extract_version(content),
        pages: pages,
        complete: complete
      )
    end

    private

      def http_get(uri, **options)
        super(uri, **options, raise_on_error: options.fetch(:raise_on_error, false), max_size: MAX_SIZE)
      end

      # --- Index detection ---

      # An index-style llms.txt has many markdown links and little prose content.
      # Heuristic: if there are >= 5 links to .md/.txt files and the ratio of
      # link-lines to total non-empty lines is > 40%, treat as index.
      def index_style?(content)
        links = extract_doc_links(content)
        return false if links.size < 5

        non_empty = content.lines.count { |l| l.strip.length > 0 }
        return false if non_empty == 0

        link_lines = content.lines.count { |l| l.match?(/\[.+?\]\(.+?\)/) }
        link_lines.to_f / non_empty > 0.4
      end

      # Extract markdown links that point to documentation files.
      # Returns array of { title:, path: } hashes.
      def extract_doc_links(content)
        content.lines.filter_map do |line|
          match = line.match(/\A\s*(?:[-*]|\d+\.)\s+\[([^\]]+)\]\(([^)]+)\)/)
          next unless match

          path = match[2].strip
          next unless documentation_link?(path)

          {
            title: match[1].strip,
            path: path
          }
        end.uniq { |link| link[:path] }
      end

      # --- Link following ---

      # Returns [pages, complete] where complete is false if the total bytes budget was hit.
      def fetch_linked_pages(base_uri, index_content, on_progress: nil)
        links = extract_doc_links(index_content)
        pages = []
        total_bytes = 0
        slug_counts = Hash.new(0)
        total_links = links.size
        hit_cap = false
        safe_hosts = {}

        links.each_with_index do |link, index|
          if total_bytes >= MAX_TOTAL_BYTES
            hit_cap = true
            break
          end

          if (index + 1) % 5 == 0 || index + 1 == total_links
            on_progress&.call("Fetching linked pages", current: index + 1, total: total_links)
          end

          resolved_uri = resolve_link(base_uri, link[:path])
          next unless resolved_uri
          next unless safe_host_uri?(resolved_uri, safe_hosts)

          raw = http_get(resolved_uri)
          next unless raw
          next if raw.strip.empty?

          title, content, headings = normalize_linked_page(raw, link, resolved_uri)
          next if content.strip.empty?

          total_bytes += content.bytesize
          if total_bytes > MAX_TOTAL_BYTES && pages.any?
            hit_cap = true
            break
          end

          slug = make_slug(title.presence || link[:title], slug_counts)

          pages << {
            page_uid: slug,
            path: linked_page_path(resolved_uri, slug),
            title: title,
            url: resolved_uri.to_s,
            content: content,
            headings: headings
          }
        end

        [ pages, !hit_cap ]
      end

      def safe_host_uri?(uri, safe_hosts)
        host = uri.host.to_s.downcase
        return false if host.blank?

        safe_hosts.fetch(host) do
          safe_hosts[host] = SsrfGuard.safe_uri?(uri)
        end
      end

      def resolve_link(base_uri, path)
        if path.start_with?("http")
          URI.parse(path)
        elsif path.start_with?("/")
          # Absolute path — resolve against origin (URI.join handles port normalization)
          URI.join(base_uri, path)
        else
          # Relative path — resolve against the llms.txt file's directory
          base_dir = base_uri.path.sub(%r{/[^/]*\z}, "/")
          URI.join(base_uri, base_dir, path)
        end
      rescue URI::InvalidURIError
        nil
      end

      def extract_title_from_content(content)
        # Try frontmatter title first
        if content.start_with?("---")
          metadata = parse_frontmatter(content.split("---", 3)[1])
          return metadata["title"] if metadata["title"].present?
        end
        # Then try ATX heading
        strip_frontmatter(content).lines.first(20).each do |line|
          if (match = line.match(/\A#\s+(.+)/))
            return match[1].strip
          end
        end
        nil
      end

      # Remove YAML frontmatter (--- delimited block at start of file)
      def strip_frontmatter(content)
        return content unless content.start_with?("---")

        parts = content.split("---", 3)
        parts.length >= 3 ? parts[2].lstrip : content
      end

      # --- Metadata extraction ---

      def extract_metadata(uri, content)
        h1 = extract_first_h1(metadata_content(content))
        title = h1 if h1 && library_title?(h1)
        LibraryIdentity.from_llms(uri: uri, title: title)
      end

      def extract_first_h1(content)
        content.lines.first(10).each do |line|
          if (match = line.match(/\A#\s+(.+)/))
            title = match[1]
              .gsub(/<[^>]+>/, "")  # strip inline HTML tags
              .strip
            title = title.split(/\s+[–—-]\s+/, 2).first.to_s.strip
            return title if title.present?
          end
        end
        nil
      end

      def metadata_content(content)
        return "" if content.start_with?("---\n")

        frontmatter_index = content.index("\n---\n")
        frontmatter_index ? content[0...frontmatter_index] : content
      end

      # Returns true if the title looks like a library/project name
      # (rather than a generic section heading like "Asset versioning")
      GENERIC_TITLES = %w[
        getting\ started installation overview configuration introduction
        quick\ start asset\ versioning setup usage guide tutorial documentation
        table\ of\ contents api\ reference changelog features
      ].freeze

      def library_title?(title)
        return false if title.blank?
        !GENERIC_TITLES.any? { |g| title.casecmp(g).zero? }
      end

      # --- Section splitting (for full-content files) ---

      def split_into_sections(content, base_url)
        frontmatter_pages = split_on_frontmatter_sections(content, base_url)
        return frontmatter_pages if frontmatter_pages.any?

        heading_level = detect_split_level(content)
        return [] unless heading_level

        raw_sections = split_on_heading(content, heading_level)
        return [] if raw_sections.size <= 1 && raw_sections.first&.dig(:title).nil?

        slug_counts = Hash.new(0)
        pages = []

        raw_sections.each do |section|
          next if section[:content].strip.empty?

          slug = make_slug(section[:title], slug_counts)
          headings = extract_sub_headings(section[:content], heading_level)

          pages << {
            page_uid: slug,
            path: "#{slug}.md",
            title: section[:title],
            url: "#{base_url}##{slug}",
            content: section[:content],
            headings: headings
          }
        end

        pages
      end

      def split_on_frontmatter_sections(content, base_url)
        matches = content.to_enum(
          :scan,
          /^---\n(?<frontmatter>.*?)\n---\n(?<body>.*?)(?=^---\n|\z)/m
        ).map { Regexp.last_match }
        return [] if matches.empty?

        slug_counts = Hash.new(0)

        matches.filter_map do |match|
          metadata = parse_frontmatter(match[:frontmatter])
          body = match[:body].to_s.lstrip
          next if body.blank?

          title = metadata["title"].presence || extract_title_from_content(body) || "Overview"
          slug = make_slug(title, slug_counts)
          page_url = resolved_section_url(base_url, metadata["url"], slug)

          {
            page_uid: slug,
            path: linked_page_path(URI.parse(page_url), slug),
            title: title,
            url: page_url,
            content: body,
            headings: body.scan(/^\#{2,4}\s+(.+)$/).flatten.map(&:strip)
          }
        rescue URI::InvalidURIError
          nil
        end
      end

      def detect_split_level(content)
        h2_count = content.scan(/^##(?!#)\s+.+/).size
        return 2 if h2_count >= 2

        h1_count = content.scan(/^#(?!#)\s+.+/).size
        return 1 if h1_count >= 2

        nil
      end

      def split_on_heading(content, level)
        prefix = "#" * level
        sections = []
        current_title = nil
        current_lines = []

        content.each_line do |line|
          if line.match?(/\A#{prefix}\s+/) && !line.match?(/\A#{prefix}#/)
            if current_title || current_lines.any?
              sections << {
                title: current_title || "Overview",
                content: current_lines.join
              }
            end

            current_title = line.sub(/\A#{prefix}\s+/, "").strip
            current_lines = [ line ]
          else
            current_lines << line
          end
        end

        if current_title || current_lines.any?
          sections << {
            title: current_title || "Overview",
            content: current_lines.join
          }
        end

        sections
      end

      # --- Slug generation ---

      def make_slug(title, slug_counts)
        base = title
          .downcase
          .gsub(/[^a-z0-9\s-]/, "")
          .strip
          .gsub(/\s+/, "-")
          .gsub(/-{2,}/, "-")
          .delete_prefix("-")
          .delete_suffix("-")

        base = "section" if base.empty?

        slug_counts[base] += 1
        if slug_counts[base] > 1
          "#{base}-#{slug_counts[base]}"
        else
          base
        end
      end

      # --- Heading extraction ---

      def extract_sub_headings(content, split_level)
        min_hashes = split_level + 1
        content.scan(/^\#{#{min_hashes},6}\s+(.+)$/).flatten.map(&:strip)
      end

      # --- Fallback ---

      def fallback_single_page(content, url, display_name)
        {
          page_uid: "llms-txt",
          path: "llms.txt",
          title: display_name,
          url: url,
          content: content,
          headings: content.scan(/^\#{2,4}\s+(.+)$/).flatten.map(&:strip)
        }
      end

      def documentation_link?(path)
        return false if path.blank?

        lower = path.downcase
        return false if lower.start_with?("#", "mailto:", "tel:", "javascript:")

        return true if path.start_with?("/")
        return true unless path.include?(":")
        return false unless path.match?(/\Ahttps?:\/\//)

        absolute_documentation_link?(path)
      end

      def normalize_linked_page(raw, link, resolved_uri)
        if html_content?(raw)
          html_result = HtmlToMarkdown.convert(raw)
          content = html_result[:content].to_s.strip
          title = html_result[:title] || link[:title]
          headings = html_result[:headings]
        else
          title = extract_title_from_content(raw) || link[:title]
          content = strip_frontmatter(raw).strip
          headings = content.scan(/^\#{2,4}\s+(.+)$/).flatten.map(&:strip)
        end

        [ title, content, headings ]
      end

      def html_content?(raw)
        trimmed = raw.lstrip
        trimmed.start_with?("<!DOCTYPE html", "<html", "<body", "<main", "<article")
      end

      def linked_page_path(uri, fallback_slug)
        path = uri.path.to_s.delete_prefix("/")
        path.present? ? path : "#{fallback_slug}.md"
      end

      def resolved_section_url(base_url, section_url, slug)
        return "#{base_url}##{slug}" if section_url.blank?

        resolved_uri = resolve_link(URI.parse(base_url), section_url)
        resolved_uri ? resolved_uri.to_s : "#{base_url}##{slug}"
      end

      def extract_version(content)
        versions = content.scan(/^version:\s*["']?([^"'\n]+)["']?\s*$/).flatten
          .filter_map { |value| normalize_version(value) }
          .uniq
        return versions.first if versions.one?

        top_level = content.match(/^@doc-version:\s*(.+)$/)&.captures&.first
        normalize_version(top_level)
      end

      def normalize_version(value)
        text = value.to_s.strip.delete_prefix('"').delete_suffix('"').presence
        return if text.blank?

        match = text.match(/\A(?:[<>=~^ ]*)v?(\d+(?:\.\d+)*(?:[-+][A-Za-z0-9.-]+)?)\z/)
        match ? match[1] : text
      end

      def parse_frontmatter(raw_frontmatter)
        raw_frontmatter.to_s.each_line.with_object({}) do |line, metadata|
          stripped = line.strip
          next if stripped.empty?
          next unless (match = stripped.match(/\A([A-Za-z0-9_-]+):\s*(.+)\z/))

          metadata[match[1]] = match[2].strip.delete_prefix('"').delete_suffix('"')
        end
      end

      def absolute_documentation_link?(path)
        uri = URI.parse(path)
        segments = uri.path.to_s.split("/").reject(&:empty?)

        return false if segments.empty?
        return true if uri.path.match?(/\.(?:md|mdx|txt)\z/i)
        return true if segments.size > 1

        %w[docs doc guide guides learn reference api tutorial quickstart quick-start].include?(segments.first.downcase)
      rescue URI::InvalidURIError
        false
      end

      def canonical_llms_source_url(url)
        url.sub(%r{/llms(?:-full|-small)?\.txt$}, "/llms.txt")
      end
  end
end
