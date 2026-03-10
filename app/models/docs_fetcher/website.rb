# frozen_string_literal: true

require "net/http"
require "nokogiri"
require "set"

module DocsFetcher
  # Multi-page website crawler that discovers and fetches all documentation pages
  # by following links from a seed URL. Converts HTML to clean Markdown via
  # HtmlToMarkdown (reverse_markdown).
  #
  # Supports HTTP proxy via CRAWL_PROXY_URL env var:
  #   CRAWL_PROXY_URL=http://user:pass@proxy.example.com:8080
  #
  # Strategy:
  # 1. Fetch the seed URL and extract all same-domain links
  # 2. BFS-crawl discovered links, staying within the domain and path prefix
  # 3. Convert HTML to Markdown, stripping nav/chrome
  # 4. Return structured Result with all pages in Markdown format
  class Website
    MAX_PAGES = 1000
    MAX_TOTAL_BYTES = 50_000_000   # 50MB total content budget
    MAX_PAGE_SIZE = 1_000_000      # 1MB per page
    MAX_REDIRECTS = 3
    CRAWL_DELAY = 0.25             # 250ms between requests

    USER_AGENT = "ContextQMD-Registry/1.0"

    # URL patterns to skip — not documentation content
    SKIP_EXTENSIONS = %w[
      .png .jpg .jpeg .gif .svg .ico .webp
      .css .js .json .xml .rss .atom
      .pdf .zip .tar .gz .tgz
      .woff .woff2 .ttf .eot
      .mp3 .mp4 .avi .mov
    ].freeze

    # Query parameters that indicate tracking/non-content URLs
    SKIP_QUERY_PATTERNS = %w[utm_ ref= source= campaign=].freeze

    def fetch(url)
      seed_uri = URI.parse(url.strip)
      @domain = seed_uri.host
      @scheme = seed_uri.scheme
      @base_path = compute_base_path(seed_uri.path)

      pages = crawl(seed_uri)
      raise "No content found at #{url}" if pages.empty?

      host = @domain.gsub(/^www\./, "")
      parts = host.split(".")

      # Derive library identity from domain:
      #   docs.example.com → example
      #   stimulus.hotwired.dev → stimulus
      namespace = if %w[docs api www dev].include?(parts.first) && parts.length >= 3
        parts[1].downcase
      else
        parts.first.downcase
      end
      name = namespace
      site_title = pages.first&.dig(:title) || @domain

      Result.new(
        namespace: namespace,
        name: name,
        display_name: site_title,
        homepage_url: url,
        aliases: [ name ],
        version: nil,
        pages: pages
      )
    end

    private

      # --- Crawling ---

      def crawl(seed_uri)
        queue = [ seed_uri.to_s ]
        visited = Set.new
        pages = []
        total_bytes = 0

        while queue.any? && pages.size < MAX_PAGES && total_bytes < MAX_TOTAL_BYTES
          current_url = queue.shift
          normalized = normalize_url(current_url)
          next if visited.include?(normalized)

          visited.add(normalized)
          sleep(CRAWL_DELAY) if pages.any? # polite delay (skip for first request)

          uri = URI.parse(current_url)
          html = http_get_with_redirects(uri)
          next unless html

          doc = Nokogiri::HTML(html)

          # Discover new links before content extraction
          discover_links(doc, uri).each do |link|
            norm_link = normalize_url(link)
            queue.push(link) unless visited.include?(norm_link)
          end

          # Convert HTML to Markdown via shared helper
          result = HtmlToMarkdown.convert(html)
          content = result[:content]
          next if content.nil? || content.strip.empty?
          next if content.bytesize > MAX_PAGE_SIZE

          total_bytes += content.bytesize
          page_uid = url_to_page_uid(uri)

          pages << {
            page_uid: page_uid,
            path: page_uid + ".md",
            title: result[:title] || @domain,
            url: current_url,
            content: content,
            headings: result[:headings]
          }
        end

        pages
      end

      # --- Link discovery ---

      def discover_links(doc, current_uri)
        links = []

        doc.css("a[href]").each do |anchor|
          href = anchor["href"].to_s.strip
          next if href.empty?

          resolved = resolve_url(href, current_uri)
          next unless resolved
          next unless same_domain?(resolved)
          next unless within_path_prefix?(resolved)
          next if skip_url?(resolved)

          links << resolved.to_s
        end

        links.uniq
      end

      def resolve_url(href, base_uri)
        # Skip fragment-only links, javascript:, mailto:, tel:
        return nil if href.start_with?("#", "javascript:", "mailto:", "tel:", "data:")

        # Strip fragment
        href = href.split("#").first.to_s
        return nil if href.empty?

        begin
          resolved = URI.join(base_uri, href)
          # Normalize to http/https only
          return nil unless %w[http https].include?(resolved.scheme)
          resolved
        rescue URI::InvalidURIError, URI::BadURIError
          nil
        end
      end

      def same_domain?(uri)
        uri.host&.downcase == @domain&.downcase
      end

      def within_path_prefix?(uri)
        # If the base path is "/" (root), allow everything on the domain
        return true if @base_path == "/"

        path = uri.path.to_s.downcase
        base = @base_path.downcase

        # Allow the exact base path and anything under it
        path.start_with?(base)
      end

      def skip_url?(uri)
        path = uri.path.to_s.downcase

        # Skip files with non-doc extensions
        return true if SKIP_EXTENSIONS.any? { |ext| path.end_with?(ext) }

        # Skip URLs with tracking query params
        query = uri.query.to_s
        return true if SKIP_QUERY_PATTERNS.any? { |pat| query.include?(pat) }

        # Skip common non-doc paths
        return true if path.match?(%r{/(assets|static|images|downloads|uploads|feeds?|api/v\d)/})

        false
      end

      # --- URL normalization ---

      def normalize_url(url_string)
        uri = URI.parse(url_string)
        # Remove fragment, normalize trailing slash, downcase host
        path = uri.path.to_s.chomp("/")
        path = "/" if path.empty?
        "#{uri.scheme}://#{uri.host&.downcase}#{path}"
      rescue URI::InvalidURIError
        url_string
      end

      def compute_base_path(path)
        # Derive the base directory from the seed URL:
        #   /handbook/introduction → /handbook    (strip leaf to find siblings)
        #   /docs/v2/guide.html   → /docs/v2     (strip file to find siblings)
        #   /docs                  → /docs        (single segment = section root)
        #   /docs/                 → /docs        (trailing slash stripped)
        #   /                      → /
        clean = path.to_s.chomp("/")
        return "/" if clean.empty? || clean == "/"

        segments = clean.delete_prefix("/").split("/")

        # Single segment (e.g. /docs): treat as section root, don't go broader
        return clean if segments.length == 1

        # Multi-segment: strip the last segment to allow discovering siblings
        parent = File.dirname(clean)
        parent == "." ? "/" : parent
      end

      def url_to_page_uid(uri)
        path = uri.path.to_s
          .delete_prefix("/")
          .delete_suffix("/")
          .gsub(/\.[a-z]+\z/i, "") # strip file extension
          .tr("/", "-")
          .downcase
          .gsub(/[^a-z0-9-]/, "-")
          .gsub(/-+/, "-")
          .delete_prefix("-")
          .delete_suffix("-")

        path.empty? ? "index" : path
      end

      # --- HTTP ---

      def http_get_with_redirects(uri, redirects_remaining = MAX_REDIRECTS)
        response = http_request(uri)

        case response
        when Net::HTTPSuccess
          body = response.body.force_encoding("UTF-8")
          content_type = response["content-type"].to_s
          # Only process HTML pages
          return nil unless content_type.include?("text/html") || content_type.empty?
          body.bytesize > MAX_PAGE_SIZE ? nil : body
        when Net::HTTPRedirection
          return nil if redirects_remaining <= 0
          location = response["location"]
          return nil unless location

          begin
            redirect_uri = URI.join(uri, location)
            http_get_with_redirects(redirect_uri, redirects_remaining - 1)
          rescue URI::InvalidURIError
            nil
          end
        else
          nil
        end
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED,
             Errno::ECONNRESET, SocketError, OpenSSL::SSL::SSLError => e
        Rails.logger.debug { "Website crawl failed for #{uri}: #{e.message}" }
        nil
      end

      def http_request(uri)
        proxy = ProxyPool.next_proxy
        http = Net::HTTP.new(uri.hostname, uri.port,
          proxy&.host, proxy&.port, proxy&.user, proxy&.password)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 10
        http.read_timeout = 15

        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = USER_AGENT
        request["Accept"] = "text/html"
        http.request(request)
      end
  end
end
