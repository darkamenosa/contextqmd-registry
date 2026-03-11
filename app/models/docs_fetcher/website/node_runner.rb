# frozen_string_literal: true

require "json"
require "open3"
require "shellwords"
require "tmpdir"
require "digest"

module DocsFetcher
  class Website
    # Browser-rendered website crawler implemented as a Node child process.
    # Spawns `node script/crawlers/website/index.mjs` with JSON input on stdin,
    # reads NDJSON progress events from stdout, and collects the result artifact.
    class NodeRunner
      def fetch(crawl_request, on_progress: nil)
        uri = URI.parse(crawl_request.url)
        proxy_lease = ProxyPool.checkout(
          scope: proxy_scope,
          target_host: uri.host,
          session_key: proxy_session_key(crawl_request),
          sticky_session: true
        )

        Dir.mktmpdir("contextqmd-website-node-") do |tmpdir|
          output_path = File.join(tmpdir, "result.json")
          payload = build_payload(crawl_request, output_path, proxy_lease&.crawl_proxy_config)
          artifact = run_crawler(payload, on_progress: on_progress)
          result = build_result(crawl_request.url, artifact.fetch("pages", []))

          record_proxy_success(proxy_lease, uri)
          result
        end
      rescue DocsFetcher::TransientFetchError, DocsFetcher::PermanentFetchError => error
        record_proxy_failure(proxy_lease, uri, error)
        raise
      ensure
        proxy_lease&.release!
      end

      def ready?
        script_path.exist? && system(*readiness_command, chdir: Rails.root.to_s, out: File::NULL, err: File::NULL)
      rescue Errno::ENOENT
        false
      end

      private

        def build_payload(crawl_request, output_path, proxy_config)
          {
            url: crawl_request.url,
            output_path: output_path,
            user_agent: Website::RubyRunner::USER_AGENT,
            crawl_delay_ms: (Website::RubyRunner::CRAWL_DELAY * 1000).round,
            skip_extensions: Website::RubyRunner::SKIP_EXTENSIONS,
            skip_query_patterns: Website::RubyRunner::SKIP_QUERY_PATTERNS,
            exclude_path_prefixes: effective_exclude_path_prefixes(crawl_request),
            max_pages: max_pages_for(crawl_request),
            proxy: build_proxy_payload(proxy_config)
          }.compact
        end

        def run_crawler(payload, on_progress: nil)
          output_path = nil
          error = nil
          stderr_output = +""

          Open3.popen3(*command, chdir: Rails.root.to_s) do |stdin, stdout, stderr, wait_thr|
            stdin.write(JSON.generate(payload))
            stdin.close

            stdout.each_line do |line|
              event = parse_event(line)
              next unless event

              case event.fetch("type", nil)
              when "progress"
                on_progress&.call(
                  event["message"],
                  current: event["current"],
                  total: event["total"]
                )
              when "result"
                output_path = event["output_path"]
              when "error"
                error = build_error(event["message"], event["error_class"])
              end
            end

            stderr_output = stderr.read
            status = wait_thr.value

            if status.success? && output_path.present?
              return JSON.parse(File.read(output_path))
            end
          end

          raise error if error

          message = stderr_output.presence || "Node website crawler failed"
          raise DocsFetcher::TransientFetchError, message
        rescue JSON::ParserError => error
          raise DocsFetcher::PermanentFetchError, "Invalid node crawler output: #{error.message}"
        rescue Errno::ENOENT => error
          raise DocsFetcher::TransientFetchError, "Node website crawler command failed: #{error.message}"
        end

        def parse_event(line)
          return if line.blank?

          JSON.parse(line)
        end

        def build_error(message, error_class)
          case error_class
          when "permanent"
            DocsFetcher::PermanentFetchError.new(message)
          else
            DocsFetcher::TransientFetchError.new(message)
          end
        end

        def build_result(source_url, pages)
          converted_pages = pages.filter_map { |page| build_page(page) }
          raise DocsFetcher::PermanentFetchError, "No content found at #{source_url}" if converted_pages.empty?

          domain = URI.parse(source_url).host
          host = domain.to_s.gsub(/^www\./, "")
          parts = host.split(".")

          namespace = if %w[docs api www dev].include?(parts.first) && parts.length >= 3
            parts[1].downcase
          else
            parts.first.to_s.downcase
          end
          name = namespace
          site_title = converted_pages.first[:title].presence || domain

          CrawlResult.new(
            namespace: namespace,
            name: name,
            display_name: site_title,
            homepage_url: source_url,
            aliases: [ name ],
            version: nil,
            pages: converted_pages,
            complete: false
          )
        end

        def build_page(page_data)
          url = page_data.fetch("url")
          html = page_data.fetch("html")
          result = HtmlToMarkdown.convert(html)
          content = result[:content].to_s.strip
          return if content.blank?

          uri = URI.parse(url)
          page_uid = url_to_page_uid(uri)

          {
            page_uid: page_uid,
            path: "#{page_uid}.md",
            title: result[:title] || uri.host,
            url: url,
            content: content,
            headings: result[:headings]
          }
        rescue URI::InvalidURIError
          nil
        end

        def url_to_page_uid(uri)
          path = uri.path.to_s
            .delete_prefix("/")
            .delete_suffix("/")
            .gsub(/\.[a-z]+\z/i, "")
            .tr("/", "-")
            .downcase
            .gsub(/[^a-z0-9-]/, "-")
            .gsub(/-+/, "-")
            .delete_prefix("-")
            .delete_suffix("-")

          path.empty? ? "index" : path
        end

        def load_crawl_rules(crawl_request)
          return {} unless crawl_request.library_id.present?

          crawl_request.library&.crawl_rules || {}
        end

        def effective_exclude_path_prefixes(crawl_request)
          rules = load_crawl_rules(crawl_request)
          Website::RubyRunner::DEFAULT_EXCLUDE_PATH_PREFIXES + Array(rules["website_exclude_path_prefixes"])
        end

        def build_proxy_payload(proxy_config)
          return unless proxy_config

          proxy_uri = proxy_config.to_uri
          bypass = normalized_proxy_bypass(proxy_config.bypass)

          {
            server: "#{proxy_uri.scheme}://#{proxy_uri.host}:#{proxy_uri.port}",
            username: proxy_uri.user,
            password: proxy_uri.password,
            bypass: bypass
          }.compact
        end

        def command
          override = ENV["CONTEXTQMD_WEBSITE_NODE_COMMAND"]
          return Shellwords.split(override) if override.present?

          [ "node", script_path.to_s ]
        end

        def readiness_command
          [
            "node",
            "--input-type=module",
            "-e",
            "import { chromium } from 'playwright'; import { access } from 'node:fs/promises'; await access(chromium.executablePath());"
          ]
        end

        def script_path
          Rails.root.join("script/crawlers/website/index.mjs")
        end

        def proxy_scope
          "website"
        end

        def max_pages_for(crawl_request)
          metadata = crawl_request.respond_to?(:metadata) ? (crawl_request.metadata || {}) : {}
          raw_value = metadata["website_max_pages"] || metadata[:website_max_pages]
          parsed = raw_value.to_i
          parsed.positive? ? parsed : nil
        end

        def normalized_proxy_bypass(value)
          case value
          when String
            value.strip.presence
          when Array
            value.filter_map { |item| item.to_s.strip.presence }.join(",").presence
          else
            nil
          end
        end

        def proxy_session_key(crawl_request)
          identifier = if crawl_request.respond_to?(:id) && crawl_request.id.present?
            crawl_request.id
          else
            Digest::SHA256.hexdigest(crawl_request.url.to_s)
          end

          "website:#{identifier}"
        end

        def record_proxy_success(proxy_config, uri)
          proxy_config&.record_success(target_host: uri.host)
        end

        def record_proxy_failure(proxy_config, uri, error)
          proxy_config&.record_failure(error_class: error.class.name, target_host: uri.host)
        end
    end
  end
end
