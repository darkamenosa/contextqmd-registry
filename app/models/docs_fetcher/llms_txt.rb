# frozen_string_literal: true

require "net/http"

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
    MAX_SIZE = 50_000_000       # 50 MB per fetched file
    MAX_TOTAL_BYTES = 20_000_000 # 20 MB total content budget
    MAX_PAGES = 500
    MAX_LINK_FETCHES = 200      # max linked pages to fetch from an index

    def fetch(url)
      uri = URI.parse(url.strip)
      content = nil
      used_full = false

      # Try llms-full.txt first if URL points to llms.txt
      if uri.path.end_with?("/llms.txt")
        full_uri = uri.dup
        full_uri.path = uri.path.sub(/\/llms\.txt\z/, "/llms-full.txt")
        full_content = http_get(full_uri)
        if full_content && full_content.strip.length > 100
          content = full_content
          uri = full_uri
          used_full = true
        end
      end

      content ||= http_get(uri)
      raise "Failed to fetch #{url}" unless content

      metadata = extract_metadata(uri, content)

      # Decide strategy: index with links or inline content?
      if !used_full && index_style?(content)
        pages = fetch_linked_pages(uri, content)
      else
        pages = split_into_sections(content, url)
      end

      if pages.empty?
        pages = [ fallback_single_page(content, url, metadata[:display_name]) ]
      end

      Result.new(
        namespace: metadata[:namespace],
        name: metadata[:name],
        display_name: metadata[:display_name],
        homepage_url: url.sub(%r{/llms(?:-full)?\.txt$}, ""),
        aliases: metadata[:aliases],
        version: nil,
        pages: pages
      )
    end

    private

      # --- HTTP ---

      def http_get(uri, redirect_limit: 5)
        raise "Too many redirects" if redirect_limit <= 0

        proxy = ProxyPool.next_proxy
        http = Net::HTTP.new(uri.hostname, uri.port,
          proxy&.host, proxy&.port, proxy&.user, proxy&.password)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 10
        http.read_timeout = 30

        response = http.request(Net::HTTP::Get.new(uri))

        if response.is_a?(Net::HTTPRedirection) && response["location"]
          return http_get(URI.join(uri, response["location"]), redirect_limit: redirect_limit - 1)
        end

        return nil unless response.is_a?(Net::HTTPSuccess)

        body = response.body.force_encoding("UTF-8")
        body.bytesize > MAX_SIZE ? body.byteslice(0, MAX_SIZE) : body
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
        links = []
        content.scan(/\[([^\]]+)\]\(([^)]+)\)/).each do |title, path|
          # Only follow links to markdown/text files or relative paths
          next unless path.match?(/\.(?:md|mdx|txt)\z/i) || path.start_with?("/")
          next if path.start_with?("http") && !path.match?(/\.(?:md|mdx|txt)\z/i)
          links << { title: title.strip, path: path.strip }
        end
        links.uniq { |l| l[:path] }
      end

      # --- Link following ---

      def fetch_linked_pages(base_uri, index_content)
        links = extract_doc_links(index_content)
        pages = []
        total_bytes = 0
        slug_counts = Hash.new(0)

        links.first(MAX_LINK_FETCHES).each do |link|
          break if total_bytes >= MAX_TOTAL_BYTES
          break if pages.size >= MAX_PAGES

          resolved_uri = resolve_link(base_uri, link[:path])
          next unless resolved_uri

          raw = http_get(resolved_uri)
          next unless raw
          next if raw.strip.empty?

          title = extract_title_from_content(raw) || link[:title]
          content = strip_frontmatter(raw)
          next if content.strip.empty?

          total_bytes += content.bytesize
          break if total_bytes > MAX_TOTAL_BYTES && pages.any?

          headings = content.scan(/^\#{2,4}\s+(.+)$/).flatten.map(&:strip)
          slug = make_slug(link[:title], slug_counts)

          pages << {
            page_uid: slug,
            path: link[:path].delete_prefix("/"),
            title: title,
            url: resolved_uri.to_s,
            content: content,
            headings: headings
          }
        end

        pages
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
          fm = content.split("---", 3)[1]
          if fm && (match = fm.match(/^title:\s*["']?(.+?)["']?\s*$/))
            return match[1].strip
          end
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
        host = uri.host.gsub(/^www\./, "")
        namespace = host.split(".").first.downcase
        h1 = extract_first_h1(content)
        title = h1 && library_title?(h1) ? h1 : namespace.tr("-", " ").gsub(/\b\w/, &:upcase)

        name_suffix = uri.path.include?("llms-full") ? "llms-full-txt" : "llms-txt"
        name = "#{namespace}-#{name_suffix}"

        aliases = [ namespace, host.split(".")[0..1].join(".") ].uniq

        {
          namespace: namespace,
          name: name,
          display_name: title,
          aliases: aliases
        }
      end

      def extract_first_h1(content)
        content.lines.first(10).each do |line|
          if (match = line.match(/\A#\s+(.+)/))
            title = match[1]
              .gsub(/<[^>]+>/, "")  # strip inline HTML tags
              .strip
            return title if title.present?
          end
        end
        nil
      end

      # Returns true if the title looks like a library/project name
      # (rather than a generic section heading like "Asset versioning")
      def library_title?(title)
        return false if title.blank?
        # Generic section titles are usually 1-3 common words
        generic = /\A(getting started|installation|overview|configuration|introduction|
          quick start|asset versioning|setup|usage|guide|tutorial|documentation)\z/ix
        !title.match?(generic)
      end

      # --- Section splitting (for full-content files) ---

      def split_into_sections(content, base_url)
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
  end
end
