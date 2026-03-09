# frozen_string_literal: true

require "net/http"

module DocsFetcher
  # Fetches documentation from an llms.txt or llms-full.txt file and splits
  # the content into individual pages by H2 (or H1) sections.
  #
  # The llms.txt format is a markdown file optimized for LLM consumption.
  # A typical file begins with `# Title`, followed by an overview paragraph,
  # then dozens of `## Section` blocks each covering a specific topic.
  class LlmsTxt
    MAX_SIZE = 50_000_000 # 50 MB — llms-full.txt files can be several MB

    def fetch(url)
      uri = URI.parse(url.strip)
      content = http_get(uri)
      raise "Failed to fetch #{url}" unless content

      metadata = extract_metadata(uri, content)
      sections = split_into_sections(content, url)

      if sections.empty?
        sections = [ fallback_single_page(content, url, metadata[:display_name]) ]
      end

      Result.new(
        namespace: metadata[:namespace],
        name: metadata[:name],
        display_name: metadata[:display_name],
        homepage_url: url.sub(%r{/llms(?:-full)?\.txt$}, ""),
        aliases: metadata[:aliases],
        version: nil,
        pages: sections
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

      # --- Metadata extraction ---

      def extract_metadata(uri, content)
        host = uri.host.gsub(/^www\./, "")
        namespace = host.split(".").first.downcase
        title = extract_first_h1(content) || namespace.capitalize

        name_suffix = uri.path.include?("llms-full") ? "llms-full-txt" : "llms-txt"
        name = "#{namespace}-#{name_suffix}"

        aliases = [ namespace, host.split(".")[0..1].join(".") ].uniq

        {
          namespace: namespace,
          name: name,
          display_name: "#{title} (llms.txt)",
          aliases: aliases
        }
      end

      def extract_first_h1(content)
        content.lines.first(10).each do |line|
          if (match = line.match(/\A#\s+(.+)/))
            return match[1].strip
          end
        end
        nil
      end

      # --- Section splitting ---

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

      # Determine whether to split on H2 or H1. Prefer H2 if there are at
      # least 2 of them; otherwise fall back to H1.
      def detect_split_level(content)
        h2_count = content.scan(/^##(?!#)\s+.+/).size
        return 2 if h2_count >= 2

        h1_count = content.scan(/^#(?!#)\s+.+/).size
        return 1 if h1_count >= 2

        nil
      end

      # Split content into sections based on the given heading level.
      # Returns an array of { title:, content: } hashes.
      # Text before the first heading becomes an "Overview" section.
      def split_on_heading(content, level)
        prefix = "#" * level
        sections = []
        current_title = nil
        current_lines = []

        content.each_line do |line|
          if line.match?(/\A#{prefix}\s+/) && !line.match?(/\A#{prefix}#/)
            # Flush the previous section
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

        # Flush the last section
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

      # Extract sub-headings that are deeper than the split level.
      # For example, if we split on H2, extract H3 and H4 headings.
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
