# frozen_string_literal: true

require "nokogiri"
require "set"
require "digest"

module DocsFetcher
  class Website
    # BFS HTML crawler implemented in pure Ruby.
    # Discovers and fetches documentation pages by following links from a seed URL.
    # Converts HTML to clean Markdown via HtmlToMarkdown (reverse_markdown).
    class RubyRunner
      include HttpFetching
      include ScopePolicy
      include PageUidEncoding

      MAX_REDIRECTS = 3
      CRAWL_DELAY = 0.25 # 250ms between requests

      USER_AGENT = "ContextQMD-Registry/1.0"

      # URL patterns to skip — not documentation content
      SKIP_EXTENSIONS = %w[
        .png .jpg .jpeg .gif .svg .ico .webp
        .css .js .json .xml .rss .atom
        .pdf .zip .tar .gz .tgz
        .woff .woff2 .ttf .eot
        .mp3 .mp4 .avi .mov
        .db .sqlite .sqlite3 .sql .dump
        .csv .tsv .parquet .duckdb
        .doc .docx .xls .xlsx .ppt .pptx
        .7z .rar .dmg .exe .bin .wasm
      ].freeze

      # Query parameters that indicate tracking/non-content URLs
      SKIP_QUERY_PATTERNS = %w[utm_ ref= source= campaign=].freeze

      # Default URL path prefixes to exclude from website crawls.
      # Per-library config adds to these (union).
      DEFAULT_EXCLUDE_PATH_PREFIXES = %w[
        /blog/ /changelog/ /releases/ /pricing/ /login/ /signup/
        /account/ /admin/ /tag/ /category/ /author/ /feed/
      ].freeze

      def probe_version(url)
        uri = URI.parse(url.strip)
        body = http_get(
          uri,
          raise_on_error: true,
          user_agent: USER_AGENT,
          accept: "text/html,application/xhtml+xml,application/xml,text/xml;q=0.9,*/*;q=0.8",
          read_timeout: 10,
          max_size: 250_000,
          oversize: :truncate,
          allowed_content_types: [ "text/html", "application/xhtml+xml", "application/xml", "text/xml" ]
        )
        return nil if body.blank?

        {
          signature: website_probe_signature(body),
          crawl_url: url
        }
      end

      def fetch(crawl_request, on_progress: nil)
        url = crawl_request.url
        seed_uri = URI.parse(url.strip)
        setup_crawl_context(crawl_request, seed_uri)

        on_progress&.call("Crawling #{@domain}")
        pages = crawl(seed_uri, on_progress: on_progress)
        raise DocsFetcher::PermanentFetchError, "No content found at #{url}" if pages.empty?

        identity = LibraryIdentity.from_website(
          uri: seed_uri,
          title: pages.first&.dig(:title)
        )

        CrawlResult.new(
          slug: identity[:slug],
          namespace: identity[:namespace],
          name: identity[:name],
          display_name: identity[:display_name],
          homepage_url: url,
          aliases: identity[:aliases],
          version: nil,
          pages: pages,
          complete: false  # website crawl is always bounded/partial
        )
      ensure
        @proxy_lease&.release!
        @proxy_lease = nil
      end

      def fetch_batch(crawl_request, urls)
        seed_uri = URI.parse(crawl_request.url.strip)
        setup_crawl_context(crawl_request, seed_uri)

        urls.filter_map do |current_url|
          uri = URI.parse(current_url)
          page_response = normalize_page_response(http_get_with_redirects(uri), requested_uri: uri)
          next unless page_response
          next if page_response[:status] == :skipped

          html = page_response.fetch(:body)
          final_uri = page_response.fetch(:final_uri)

          doc = Nokogiri::HTML(html)
          result = HtmlToMarkdown.convert(html)
          content = result[:content].to_s.strip
          page_uid = url_to_page_uid(final_uri)

          {
            requested_url: current_url,
            url: final_uri.to_s,
            page: content.present? ? {
              page_uid: page_uid,
              path: "#{page_uid}.md",
              title: result[:title] || @domain,
              url: final_uri.to_s,
              content: content,
              headings: result[:headings]
            } : nil,
            links: discover_links(doc, final_uri)
          }
        rescue URI::InvalidURIError
          nil
        end
      ensure
        @proxy_lease&.release!
        @proxy_lease = nil
      end

      private

        def setup_crawl_context(crawl_request, seed_uri)
          @domain = seed_uri.host
          @scheme = seed_uri.scheme
          @base_path = compute_base_path(seed_uri.path)
          @crawl_rules = load_crawl_rules(crawl_request)
          @max_pages = max_pages_for(crawl_request)
          @proxy_lease = ProxyPool.checkout(
            scope: proxy_scope,
            target_host: @domain,
            session_key: proxy_session_key(crawl_request),
            sticky_session: true
          )
        end

        # --- Crawling ---

        def crawl(seed_uri, on_progress: nil)
          queue = [ seed_uri.to_s ]
          visited = Set.new
          pages = []
          crawled_count = 0

          while queue.any? && crawl_more_pages?(crawled_count)
            current_url = queue.shift
            next if visited_url?(visited, current_url)

            mark_visited_urls(visited, current_url)
            sleep(CRAWL_DELAY) if pages.any? # polite delay (skip for first request)

            uri = URI.parse(current_url)
            page_response = normalize_page_response(http_get_with_redirects(uri), requested_uri: uri)
            next unless page_response

            if page_response[:status] == :skipped
              raise_if_seed_redirected_outside_scope!(current_url, seed_uri, page_response)
              next
            end

            html = page_response.fetch(:body)
            final_uri = page_response.fetch(:final_uri)
            mark_visited_urls(visited, final_uri)
            crawled_count += 1

            doc = Nokogiri::HTML(html)

            # Discover new links before content extraction
            if crawl_more_pages?(crawled_count)
              discover_links(doc, final_uri).each do |link|
                queue.push(link) unless visited_url?(visited, link)
              end
            end

            # Convert HTML to Markdown via shared helper
            result = HtmlToMarkdown.convert(html)
            content = result[:content]
            next if content.nil? || content.strip.empty?
            page_uid = url_to_page_uid(final_uri)

            pages << {
              page_uid: page_uid,
              path: page_uid + ".md",
              title: result[:title] || @domain,
              url: final_uri.to_s,
              content: content,
              headings: result[:headings]
            }

            if pages.size % 10 == 0
              on_progress&.call("Discovered #{pages.size} pages so far")
            end
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
          return nil if href.start_with?("#", "javascript:", "mailto:", "tel:", "data:")

          href = href.split("#").first.to_s
          return nil if href.empty?

          begin
            resolved = URI.join(base_uri, href)
            return nil unless %w[http https].include?(resolved.scheme)
            resolved
          rescue URI::InvalidURIError, URI::BadURIError
            nil
          end
        end

        def same_domain?(uri)
          same_domain_for_website?(uri, @domain)
        end

        def within_path_prefix?(uri)
          within_base_path_for_website?(uri, @base_path)
        end

        def skip_url?(uri)
          path = uri.path.to_s.downcase

          return true if SKIP_EXTENSIONS.any? { |ext| path.end_with?(ext) }

          query = uri.query.to_s
          return true if SKIP_QUERY_PATTERNS.any? { |pat| query.include?(pat) }

          return true if path.match?(%r{/(assets|static|images|downloads|uploads|feeds?|api/v\d)/})

          # Check against default + library-specific path prefix excludes
          return true if effective_exclude_path_prefixes.any? { |prefix| path.start_with?(prefix) }

          false
        end

        # --- Crawl rules ---

        def load_crawl_rules(crawl_request)
          return {} unless crawl_request.library_id.present?

          crawl_request.library&.crawl_rules || {}
        end

        def effective_exclude_path_prefixes
          rules = @crawl_rules || {}
          DEFAULT_EXCLUDE_PATH_PREFIXES + Array(rules["website_exclude_path_prefixes"])
        end

        def max_pages_for(crawl_request)
          metadata = crawl_request.respond_to?(:metadata) ? (crawl_request.metadata || {}) : {}
          raw_value = metadata["website_max_pages"] || metadata[:website_max_pages]
          parsed = raw_value.to_i
          parsed.positive? ? parsed : nil
        end

        # --- URL normalization ---

        def normalize_url(url_string)
          uri = URI.parse(url_string)
          path = uri.path.to_s.chomp("/")
          path = "/" if path.empty?
          "#{uri.scheme}://#{uri.host&.downcase}#{path}"
        rescue URI::InvalidURIError
          url_string
        end

        # --- HTTP ---

        def http_get_with_redirects(uri, redirects_remaining = MAX_REDIRECTS)
          return if redirects_remaining <= 0

          if @proxy_lease.nil? && !SsrfGuard.safe_uri?(uri)
            raise DocsFetcher::PermanentFetchError, "SSRF blocked: #{uri.host} resolves to private address"
          end

          response = perform_http_get(
            uri,
            @proxy_lease&.crawl_proxy_config,
            accept: "text/html",
            user_agent: USER_AGENT,
            open_timeout: 10,
            read_timeout: 15
          )
          record_proxy_success(@proxy_lease, uri)

          if response.is_a?(Net::HTTPRedirection) && response["location"]
            redirect_uri = URI.join(uri, response["location"])
            unless SsrfGuard.safe_uri?(redirect_uri)
              raise DocsFetcher::PermanentFetchError, "Redirect to private address: #{redirect_uri.host}"
            end

            return http_get_with_redirects(redirect_uri, redirects_remaining - 1)
          end

          return unless response.is_a?(Net::HTTPSuccess)

          content_type = response["content-type"].to_s
          return unless content_type.empty? || content_type.include?("text/html")

          body = response.body.to_s.dup.force_encoding("UTF-8")
          finalize_page_response(uri, body)
        rescue DocsFetcher::PermanentFetchError
          raise
        rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED,
               Errno::ECONNRESET, SocketError, OpenSSL::SSL::SSLError => error
          record_proxy_failure(@proxy_lease, uri, error)
          nil
        end

        def finalize_page_response(final_uri, body)
          return skipped_page_response(final_uri) unless crawlable_redirect_target?(final_uri)

          {
            status: :ok,
            body: body,
            final_uri: final_uri
          }
        end

        def crawlable_redirect_target?(uri)
          uri.present? &&
            crawlable_page_uri?(uri, domain: @domain, base_path: @base_path) &&
            !skip_url?(uri)
        end

        def normalize_page_response(page_response, requested_uri:)
          return if page_response.blank?
          return page_response if page_response.is_a?(Hash)

          {
            status: :ok,
            body: page_response,
            final_uri: requested_uri
          }
        end

        def visited_url?(visited, url)
          visited.include?(normalize_url(url.to_s))
        end

        def mark_visited_urls(visited, *urls)
          urls.each do |url|
            next if url.blank?

            visited.add(normalize_url(url.to_s))
          end
        end

        def skipped_page_response(uri)
          {
            status: :skipped,
            final_uri: uri,
            message: uri.present? ? submitted_url_redirected_outside_scope_message(uri) : nil
          }
        end

        def raise_if_seed_redirected_outside_scope!(current_url, seed_uri, page_response)
          return unless current_url == seed_uri.to_s
          return if page_response[:message].blank?

          raise DocsFetcher::PermanentFetchError, page_response[:message]
        end

        def proxy_scope
          "website"
        end

        def crawl_more_pages?(crawled_count)
          @max_pages.nil? || crawled_count < @max_pages
        end

        def proxy_session_key(crawl_request)
          identifier = if crawl_request.respond_to?(:id) && crawl_request.id.present?
            crawl_request.id
          else
            Digest::SHA256.hexdigest(crawl_request.url.to_s)
          end

          "website:#{identifier}"
        end

        def website_probe_signature(body)
          content = if sitemap_payload?(body)
            sitemap_probe_content(body)
          else
            html_probe_content(body)
          end

          Digest::SHA256.hexdigest(content)
        end

        def sitemap_payload?(body)
          snippet = body.to_s.lstrip
          snippet.start_with?("<?xml", "<urlset", "<sitemapindex")
        end

        def sitemap_probe_content(body)
          doc = Nokogiri::XML(body) { |config| config.strict.nonet }
          doc.remove_namespaces!
          locations = doc.css("url > loc, sitemap > loc").map { |node| node.text.to_s.strip }.reject(&:blank?).first(1000)
          locations.join("\n")
        rescue StandardError
          body.to_s
        end

        def html_probe_content(body)
          doc = Nokogiri::HTML(body)
          doc.css("script, style, noscript").remove

          title = doc.at_css("title")&.text.to_s.squish
          focus = doc.at_css("main") || doc.at_css("article") || doc.at_css("body") || doc
          text = focus.text.to_s.squish.first(20_000)

          [ title, text ].join("\n")
        rescue StandardError
          body.to_s
        end
    end
  end
end
