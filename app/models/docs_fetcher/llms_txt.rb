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
    MAX_PAGES = 500
    MAX_LINK_FETCHES = 200      # max linked pages to fetch from an index

    def fetch(crawl_request, on_progress: nil)
      url = crawl_request.url
      uri = URI.parse(url.strip)
      content = nil
      used_full = false

      # Try llms-full.txt first if URL points to llms.txt (but NOT llms-small.txt)
      if uri.path.end_with?("/llms.txt")
        on_progress&.call("Trying llms-full.txt")
        full_uri = uri.dup
        full_uri.path = uri.path.sub(/\/llms\.txt\z/, "/llms-full.txt")
        full_content = http_get(full_uri)
        if full_content && full_content.strip.length > 100
          content = full_content
          uri = full_uri
          used_full = true
        end
      end
      # llms-small.txt and llms-full.txt are used directly — no upgrade/downgrade

      on_progress&.call("Fetching #{File.basename(uri.path)}")
      content ||= http_get(uri, raise_on_error: true)
      raise DocsFetcher::TransientFetchError, "Failed to fetch #{url}" unless content

      metadata = extract_metadata(uri, content)

      # Decide strategy: index with links or inline content?
      if !used_full && index_style?(content)
        on_progress&.call("Following linked pages")
        pages, complete = fetch_linked_pages(uri, content, on_progress: on_progress)
      else
        on_progress&.call("Splitting into sections")
        pages = split_into_sections(content, url)
        complete = true # section splitting processes all content, never truncated
      end

      if pages.empty?
        pages = [ fallback_single_page(content, url, metadata[:display_name]) ]
      end

      CrawlResult.new(
        namespace: metadata[:namespace],
        name: metadata[:name],
        display_name: metadata[:display_name],
        homepage_url: url.sub(%r{/llms(?:-full|-small)?\.txt$}, ""),
        aliases: metadata[:aliases],
        version: nil,
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

      # Returns [pages, complete] where complete is false if any cap was hit.
      def fetch_linked_pages(base_uri, index_content, on_progress: nil)
        links = extract_doc_links(index_content)
        pages = []
        total_bytes = 0
        slug_counts = Hash.new(0)
        total_links = [ links.size, MAX_LINK_FETCHES ].min
        hit_cap = false

        links.first(MAX_LINK_FETCHES).each_with_index do |link, index|
          if total_bytes >= MAX_TOTAL_BYTES
            hit_cap = true
            break
          end
          if pages.size >= MAX_PAGES
            hit_cap = true
            break
          end

          if (index + 1) % 5 == 0 || index + 1 == total_links
            on_progress&.call("Fetching linked pages", current: index + 1, total: total_links)
          end

          resolved_uri = resolve_link(base_uri, link[:path])
          next unless resolved_uri
          next unless SsrfGuard.safe_uri?(resolved_uri)

          raw = http_get(resolved_uri)
          next unless raw
          next if raw.strip.empty?

          title = extract_title_from_content(raw) || link[:title]
          content = strip_frontmatter(raw)
          next if content.strip.empty?

          total_bytes += content.bytesize
          if total_bytes > MAX_TOTAL_BYTES && pages.any?
            hit_cap = true
            break
          end

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

        hit_cap = true if links.size > MAX_LINK_FETCHES

        [ pages, !hit_cap ]
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
        parts = host.split(".")

        # Derive the library identity from the domain:
        #   docs.astro.build    → namespace=astro, name=astro
        #   nextjs.org          → namespace=nextjs, name=nextjs
        #   inertia-rails.dev   → namespace=inertia-rails, name=inertia-rails
        #   api.stripe.com      → namespace=stripe, name=stripe
        namespace = if %w[docs api www dev].include?(parts.first) && parts.length >= 3
          parts[1].downcase
        else
          parts.first.downcase
        end
        name = namespace

        h1 = extract_first_h1(content)
        title = h1 && library_title?(h1) ? h1 : namespace.tr("-", " ").gsub(/\b\w/, &:upcase)

        aliases = [ namespace, name, host ].uniq

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
