# frozen_string_literal: true

require "net/http"
require "json"

module DocsFetcher
  # Fetches documentation from a GitLab repository using the GitLab API v4.
  #
  # Supports both gitlab.com and self-hosted GitLab instances.
  # Auth via GITLAB_TOKEN env var or Rails credentials.
  #
  # Strategy:
  # 1. Parse project path from URL
  # 2. Fetch repository tree recursively via GitLab API
  # 3. Score and rank markdown files by documentation relevance (shared logic with Github)
  # 4. Fetch file contents via raw API
  # 5. Return structured Result
  class Gitlab
    MAX_PAGES = 500
    MAX_FILE_SIZE = 500_000
    MAX_TOTAL_BYTES = 20_000_000

    DOC_EXTENSIONS = %w[.md .mdx .rst].freeze

    HIGH_VALUE_DIRS = %w[
      docs doc documentation guide guides
      content content/docs content/guide
      website/docs website/content
      pages/docs manual reference wiki
    ].freeze

    SKIP_DIRS = %w[
      node_modules vendor .git __pycache__ .next .nuxt
      test tests spec __tests__ fixtures
      dist build out target _build coverage .cache
    ].freeze

    SKIP_FILES = %w[
      CHANGELOG.md CHANGES.md HISTORY.md
      LICENSE.md LICENSE-MIT.md LICENSE-APACHE.md
      CODE_OF_CONDUCT.md SECURITY.md
      CONTRIBUTING.md RELEASING.md
    ].freeze

    ROOT_DOC_FILES = %w[
      README.md UPGRADING.md MIGRATION.md
      GETTING_STARTED.md QUICKSTART.md
      ARCHITECTURE.md DESIGN.md
    ].freeze

    def fetch(url)
      @host, project_path, branch = parse_gitlab_url(url)
      @api_base = "https://#{@host}/api/v4"
      @encoded_path = ERB::Util.url_encode(project_path)

      project = fetch_project_metadata
      default_branch = branch || project["default_branch"] || "main"

      tree = fetch_tree(default_branch)
      raise "Empty repository: #{project_path}" if tree.empty?

      candidates = discover_doc_files(tree)
      raise "No documentation found in #{project_path}" if candidates.empty?

      ranked = score_and_rank(candidates)
      pages = fetch_pages(default_branch, ranked)
      raise "No documentation content fetched from #{project_path}" if pages.empty?

      version = extract_version(branch)
      build_result(project_path, project, pages, version)
    end

    private

      # --- URL parsing ---

      def parse_gitlab_url(url)
        uri = URI.parse(url.strip)
        host = uri.host
        parts = uri.path.delete_prefix("/").split("/")

        # GitLab project paths can be nested: group/subgroup/project
        # /-/ separates project path from repo content paths
        separator_idx = parts.index("-")

        if separator_idx
          project_parts = parts[0...separator_idx]
          branch = parts[separator_idx + 2] if parts[separator_idx + 1] == "tree"
        else
          # No /-/ separator — try to detect project path
          # Minimum: owner/project (2 segments)
          project_parts = parts.first(parts.length.clamp(2, parts.length))
          branch = nil
        end

        project_path = project_parts.join("/")
        raise ArgumentError, "Invalid GitLab URL: #{url}" if project_path.split("/").length < 2

        [ host, project_path, branch ]
      end

      # --- API calls ---

      def fetch_project_metadata
        gitlab_api_get("/projects/#{@encoded_path}")
      end

      def fetch_tree(branch, page: 1, per_page: 100)
        items = []
        loop do
          data = gitlab_api_get(
            "/projects/#{@encoded_path}/repository/tree?ref=#{branch}&recursive=true&per_page=#{per_page}&page=#{page}"
          )
          break if data.empty?

          items.concat(data)
          break if data.size < per_page

          page += 1
          break if items.size > 10_000 # safety limit
        end
        items
      rescue StandardError => e
        Rails.logger.warn("Failed to fetch GitLab tree: #{e.message}")
        []
      end

      # --- File discovery (shared logic with Github fetcher) ---

      def discover_doc_files(tree)
        tree.select do |item|
          item["type"] == "blob" &&
            doc_extension?(item["path"]) &&
            !skip_path?(item["path"]) &&
            item["path"].bytesize < 500
        end
      end

      def doc_extension?(path)
        DOC_EXTENSIONS.any? { |ext| path.downcase.end_with?(ext) }
      end

      def skip_path?(path)
        parts = path.split("/")
        return true if parts.any? { |p| SKIP_DIRS.include?(p) }

        filename = parts.last
        return true if SKIP_FILES.any? { |f| filename.casecmp(f).zero? }

        false
      end

      # --- Scoring (same algorithm as Github fetcher) ---

      def score_and_rank(candidates)
        scored = candidates.map do |item|
          { item: item, score: score_file(item["path"]) }
        end

        scored
          .sort_by { |s| -s[:score] }
          .first(MAX_PAGES)
          .map { |s| s[:item] }
      end

      def score_file(path)
        score = 0.0
        parts = path.split("/")
        filename = parts.last
        dir_path = parts[0...-1].join("/").downcase

        if parts.length == 1
          if ROOT_DOC_FILES.any? { |f| filename.casecmp(f).zero? }
            score += 100
          elsif filename.casecmp("README.md").zero?
            score += 80
          end
        end

        HIGH_VALUE_DIRS.each do |doc_dir|
          if dir_path.start_with?(doc_dir) || dir_path == doc_dir
            score += 90
            break
          end
        end

        depth = parts.length - 1
        score -= depth * 2

        name_lower = filename.downcase
        score += 15 if name_lower.include?("getting-started") || name_lower.include?("getting_started")
        score += 10 if name_lower.include?("tutorial") || name_lower.include?("quickstart")
        score += 10 if name_lower.include?("guide") || name_lower.include?("usage")
        score += 5 if name_lower.include?("api") || name_lower.include?("reference")
        score -= 10 if parts.length > 1 && name_lower == "readme.md"

        score
      end

      # --- Content fetching ---

      def fetch_pages(branch, ranked_files)
        pages = []
        total_bytes = 0

        ranked_files.each do |item|
          break if total_bytes >= MAX_TOTAL_BYTES

          path = item["path"]
          content = fetch_raw_file(branch, path)
          next unless content
          next if content.strip.empty?
          next if content.bytesize > MAX_FILE_SIZE

          total_bytes += content.bytesize
          break if total_bytes > MAX_TOTAL_BYTES && pages.any?

          title = extract_title(content, path)
          headings = extract_headings(content)
          slug = path.delete_suffix(File.extname(path)).tr("/", "-").downcase

          pages << {
            page_uid: slug,
            path: path,
            title: title,
            url: "https://#{@host}/#{@encoded_path}/-/blob/#{branch}/#{path}",
            content: content,
            headings: headings
          }
        end

        pages
      end

      def fetch_raw_file(branch, path)
        encoded_file = ERB::Util.url_encode(path)
        data = gitlab_api_get("/projects/#{@encoded_path}/repository/files/#{encoded_file}/raw?ref=#{branch}", raw: true)
        data
      rescue StandardError
        nil
      end

      # --- Content extraction ---

      def extract_title(content, filename)
        header_region = content.lines.first(30).join
        if (match = header_region.match(/^#\s+(.+)$/))
          match[1].strip
        else
          File.basename(filename, File.extname(filename)).tr("-_", " ").gsub(/\b\w/, &:upcase)
        end
      end

      def extract_headings(content)
        content.scan(/^\#{2,4}\s+(.+)$/).flatten.map(&:strip)
      end

      # --- Version extraction ---

      def extract_version(branch)
        return nil unless branch

        cleaned = branch.sub(/\Av/i, "").sub(%r{\Arelease/}i, "")
        cleaned.match?(/\A\d/) ? cleaned : nil
      end

      # --- Result building ---

      def build_result(project_path, project, pages, version)
        parts = project_path.split("/")
        namespace = parts.first.downcase
        name = parts.last.downcase

        display_name = project["name"]&.tr("-", " ")&.gsub(/\b\w/, &:upcase) ||
                       name.tr("-", " ").split.map(&:capitalize).join(" ")

        topics = project["topics"] || project["tag_list"] || []
        aliases = ([ name, name.tr("-", "") ] + topics.first(5)).uniq

        Result.new(
          namespace: namespace,
          name: name,
          display_name: display_name,
          homepage_url: project["web_url"] || "https://#{@host}/#{project_path}",
          aliases: aliases,
          version: version,
          pages: pages
        )
      end

      # --- HTTP ---

      def gitlab_api_get(path, raw: false)
        uri = URI("#{@api_base}#{path}")
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = "ContextQMD-Registry/1.0"
        token = gitlab_token
        request["PRIVATE-TOKEN"] = token if token

        proxy = ProxyPool.next_proxy
        http = Net::HTTP.new(uri.hostname, uri.port,
          proxy&.host, proxy&.port, proxy&.user, proxy&.password)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 30

        response = http.request(request)
        raise "GitLab API error #{response.code}: #{response.body.first(200)}" unless response.is_a?(Net::HTTPSuccess)

        if raw
          response.body.force_encoding("UTF-8")
        else
          JSON.parse(response.body)
        end
      end

      def gitlab_token
        ENV["GITLAB_TOKEN"] || Rails.application.credentials.dig(:gitlab, :token)
      end
  end
end
