# frozen_string_literal: true

module DocsFetcher
  # Strategy entrypoint for website crawling.
  # Delegates to RubyRunner (BFS HTML crawler) or NodeRunner (browser-rendered child).
  #
  # This is NOT the crawler itself — it selects the right runner.
  class Website
    BROWSER_FALLBACK_PATTERNS = [
      /enable javascript/i,
      /javascript required/i,
      /requires javascript/i,
      /run this app/i,
      /\Aloading(?:\.\.\.)?\z/i
    ].freeze

    module ScopePolicy
      private

        def compute_base_path(path)
          clean = path.to_s.chomp("/")
          return "/" if clean.empty? || clean == "/"

          segments = clean.delete_prefix("/").split("/")
          return clean if segments.length == 1

          parent = File.dirname(clean)
          parent == "." ? "/" : parent
        end

        def crawlable_page_uri?(uri, domain:, base_path:)
          same_domain_for_website?(uri, domain) &&
            within_base_path_for_website?(uri, base_path)
        end

        def same_domain_for_website?(uri, domain)
          uri.host&.downcase == domain.to_s.downcase
        end

        def within_base_path_for_website?(uri, base_path)
          return true if base_path == "/"

          uri.path.to_s.downcase.start_with?(base_path.to_s.downcase)
        end

        def submitted_url_redirected_outside_scope_message(uri)
          "Submitted URL redirected outside crawl scope to #{uri}"
        end
    end

    module PageUidEncoding
      private

        def url_to_page_uid(uri)
          segments = uri.path.to_s
            .delete_prefix("/")
            .delete_suffix("/")
            .split("/")
            .reject(&:blank?)

          return "index" if segments.empty?

          encoded = segments.map.with_index do |segment, index|
            normalized = index == segments.length - 1 ? segment.sub(/\.[a-z]+\z/i, "") : segment
            encode_page_uid_segment(normalized)
          end.reject(&:blank?)

          encoded.join("-").presence || "index"
        end

        def encode_page_uid_segment(segment)
          chars = segment.to_s.each_char.filter_map do |char|
            case char
            when /[A-Za-z0-9]/
              char.downcase
            when "-"
              "-"
            when "_"
              "-underscore-"
            when ":"
              "-colon-"
            when "."
              "-dot-"
            when "+"
              "-plus-"
            else
              bytes = char.encode("UTF-8").bytes.map { |byte| format("x%02x", byte) }
              "-#{bytes.join('-')}-"
            end
          end

          chars.join
            .gsub(/-+/, "-")
            .delete_prefix("-")
            .delete_suffix("-")
        end
    end

    def probe_version(url)
      ruby_runner.probe_version(url)
    end

    def fetch(crawl_request, on_progress: nil)
      runner = select_runner(crawl_request)
      result = runner.fetch(crawl_request, on_progress: on_progress)

      if retry_with_node?(crawl_request, runner, result)
        fallback_with_node(crawl_request, on_progress: on_progress)
      else
        result
      end
    rescue DocsFetcher::PermanentFetchError => error
      if retry_with_node_after_error?(crawl_request, runner, error)
        fallback_with_node(crawl_request, on_progress: on_progress)
      else
        raise
      end
    end

    private

      def select_runner(crawl_request)
        case requested_runner(crawl_request)
        when "node"
          if node_runner.ready?
            node_runner
          else
            raise DocsFetcher::TransientFetchError, "Node website runner is not ready on this host"
          end
        else
          ruby_runner
        end
      end

      def retry_with_node?(crawl_request, runner, result)
        auto_runner?(crawl_request) &&
          runner.equal?(ruby_runner) &&
          node_runner.ready? &&
          javascript_shell?(result)
      end

      def retry_with_node_after_error?(crawl_request, runner, error)
        auto_runner?(crawl_request) &&
          runner.equal?(ruby_runner) &&
          node_runner.ready? &&
          error.message.match?(/\ANo content found/i)
      end

      def fallback_with_node(crawl_request, on_progress: nil)
        on_progress&.call("Retrying with browser-rendered crawl")
        node_runner.fetch(crawl_request, on_progress: on_progress)
      end

      def javascript_shell?(result)
        return false unless result.pages.one?

        page = result.pages.first
        content = page[:content].to_s.strip
        return false if content.blank?

        headings = Array(page[:headings])
        BROWSER_FALLBACK_PATTERNS.any? { |pattern| content.match?(pattern) } &&
          headings.empty?
      end

      def requested_runner(crawl_request)
        metadata = crawl_request.metadata || {}
        metadata["website_runner"] || metadata[:website_runner] || "auto"
      end

      def auto_runner?(crawl_request)
        requested_runner(crawl_request) == "auto"
      end

      def ruby_runner
        @ruby_runner ||= RubyRunner.new
      end

      def node_runner
        @node_runner ||= NodeRunner.new
      end
  end
end
