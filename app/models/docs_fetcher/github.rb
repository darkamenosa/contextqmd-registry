# frozen_string_literal: true

require "net/http"
require "json"

module DocsFetcher
  # Fetches documentation from a GitHub repository using the recursive tree API.
  #
  # Strategy:
  # 1. Fetch repo metadata (description, default branch, topics)
  # 2. Fetch full recursive tree in one API call
  # 3. Score and rank all markdown files by documentation relevance
  # 4. Fetch top-N files by raw content URL
  # 5. Return structured Result
  class Github
    GITHUB_API = "https://api.github.com"
    RAW_BASE = "https://raw.githubusercontent.com"

    MAX_PAGES = 500           # max pages to include
    MAX_FILE_SIZE = 500_000   # 500KB per file
    MAX_TOTAL_BYTES = 20_000_000 # 20MB total content budget

    DOC_EXTENSIONS = %w[.md .mdx .rst].freeze

    # Directories that almost always contain documentation
    HIGH_VALUE_DIRS = %w[
      docs doc documentation guide guides guides/source
      content content/docs content/guide
      website/docs website/content
      pages/docs manual reference wiki
    ].freeze

    # Directories to always skip — never contain useful docs
    SKIP_DIRS = %w[
      node_modules vendor .github .git __pycache__ .next .nuxt
      test tests spec __tests__ fixtures test_fixtures
      dist build out target _build coverage .cache
      examples/node_modules
    ].freeze

    # Files that are NOT documentation (even if they're markdown)
    SKIP_FILES = %w[
      CHANGELOG.md CHANGES.md HISTORY.md
      LICENSE.md LICENSE-MIT.md LICENSE-APACHE.md
      CODE_OF_CONDUCT.md SECURITY.md
      CODEOWNERS .github
      CONTRIBUTING.md RELEASING.md
    ].freeze

    # Root-level files worth including alongside docs
    ROOT_DOC_FILES = %w[
      README.md UPGRADING.md MIGRATION.md
      GETTING_STARTED.md QUICKSTART.md
      ARCHITECTURE.md DESIGN.md
    ].freeze

    def fetch(url)
      owner, repo, branch = parse_github_url(url)
      repo_data = fetch_repo_metadata(owner, repo)
      default_branch = branch || repo_data["default_branch"] || "main"

      tree = fetch_recursive_tree(owner, repo, default_branch)
      raise "Empty repository: #{owner}/#{repo}" if tree.empty?

      candidates = discover_doc_files(tree)
      raise "No documentation found in #{owner}/#{repo}" if candidates.empty?

      ranked = score_and_rank(candidates)
      pages = fetch_pages(owner, repo, default_branch, ranked)
      raise "No documentation content fetched from #{owner}/#{repo}" if pages.empty?

      version = extract_version(branch, repo_data)
      build_result(owner, repo, repo_data, pages, version)
    end

    private

      # --- URL parsing ---

      def parse_github_url(url)
        uri = URI.parse(url.strip)
        parts = uri.path.delete_prefix("/").split("/")
        owner = parts[0]
        repo = parts[1]&.delete_suffix(".git")
        branch = parts[3] if parts[2] == "tree"
        raise ArgumentError, "Invalid GitHub URL: #{url}" unless owner && repo
        [ owner, repo, branch ]
      end

      # --- API calls ---

      def fetch_repo_metadata(owner, repo)
        github_api_get("/repos/#{owner}/#{repo}")
      end

      def fetch_recursive_tree(owner, repo, branch)
        data = github_api_get("/repos/#{owner}/#{repo}/git/trees/#{branch}?recursive=1")
        data["tree"] || []
      rescue StandardError => e
        Rails.logger.warn("Failed to fetch tree for #{owner}/#{repo}: #{e.message}")
        []
      end

      # --- File discovery ---

      def discover_doc_files(tree)
        tree.select do |item|
          item["type"] == "blob" &&
            doc_extension?(item["path"]) &&
            !skip_path?(item["path"]) &&
            item["size"].to_i > 0 &&
            item["size"].to_i < MAX_FILE_SIZE
        end
      end

      def doc_extension?(path)
        DOC_EXTENSIONS.any? { |ext| path.downcase.end_with?(ext) }
      end

      def skip_path?(path)
        parts = path.split("/")

        # Skip files in excluded directories
        return true if parts.any? { |p| SKIP_DIRS.include?(p) }

        # Skip blacklisted filenames (case-insensitive)
        filename = parts.last
        return true if SKIP_FILES.any? { |f| filename.casecmp(f).zero? }

        false
      end

      # --- Scoring ---

      def score_and_rank(candidates)
        scored = candidates.map do |item|
          { item: item, score: score_file(item["path"], item["size"].to_i) }
        end

        scored
          .sort_by { |s| -s[:score] }
          .first(MAX_PAGES)
          .map { |s| s[:item] }
      end

      def score_file(path, size)
        score = 0.0
        parts = path.split("/")
        filename = parts.last
        dir_path = parts[0...-1].join("/").downcase

        # Root-level documentation files
        if parts.length == 1
          score += 100 if ROOT_DOC_FILES.any? { |f| filename.casecmp(f).zero? }
          score += 80 if filename.casecmp("README.md").zero?
        end

        # Files in high-value documentation directories
        HIGH_VALUE_DIRS.each do |doc_dir|
          if dir_path.start_with?(doc_dir) || dir_path == doc_dir
            score += 90
            break
          end
        end

        # Depth penalty: deeper files are less likely to be primary docs
        depth = parts.length - 1
        score -= depth * 2

        # Size signal: very small files (<500b) are likely stubs, very large (>200KB) might be auto-generated
        if size < 500
          score -= 20
        elsif size.between?(1000, 200_000)
          score += 10
        elsif size > 200_000
          score -= 5
        end

        # Filename signals
        name_lower = filename.downcase
        score += 15 if name_lower.include?("getting-started") || name_lower.include?("getting_started")
        score += 10 if name_lower.include?("tutorial") || name_lower.include?("quickstart")
        score += 10 if name_lower.include?("guide") || name_lower.include?("usage")
        score += 5 if name_lower.include?("api") || name_lower.include?("reference")
        score += 5 if name_lower.include?("install") || name_lower.include?("setup")
        score -= 20 if name_lower.include?("release_notes") || name_lower.include?("release-notes")
        score -= 30 if name_lower.match?(/\d+_\d+_release/) # e.g. "5_0_release_notes.md"

        # Subdirectory READMEs are less useful as standalone pages
        score -= 10 if parts.length > 1 && name_lower == "readme.md"

        score
      end

      # --- Content fetching ---

      def fetch_pages(owner, repo, branch, ranked_files)
        pages = []
        total_bytes = 0

        ranked_files.each do |item|
          break if total_bytes >= MAX_TOTAL_BYTES

          path = item["path"]
          content = raw_get(owner, repo, branch, path)
          next unless content
          next if content.strip.empty?

          total_bytes += content.bytesize
          break if total_bytes > MAX_TOTAL_BYTES && pages.any? # allow first file even if over budget

          title = extract_title(content, path)
          headings = extract_headings(content)
          slug = path.delete_suffix(File.extname(path)).tr("/", "-").downcase

          pages << {
            page_uid: slug,
            path: path,
            title: title,
            url: "https://github.com/#{owner}/#{repo}/blob/#{branch}/#{path}",
            content: content,
            headings: headings
          }
        end

        pages
      end

      # --- Content extraction ---

      def extract_title(content, filename)
        # Look only in the first 30 lines to avoid matching code blocks
        header_region = content.lines.first(30).join

        # Try ATX-style: # Title
        if (match = header_region.match(/^#\s+(.+)$/))
          clean_title(match[1], filename)
        # Try Setext-style: Title\n====
        elsif (match = header_region.match(/^([^\n#*`<>]{3,})\n={3,}\s*$/))
          clean_title(match[1], filename)
        else
          humanize_filename(filename)
        end
      end

      def clean_title(raw, filename)
        # Strip HTML tags, badge images, markdown links
        clean = raw.gsub(/<[^>]+>/, "")
                    .gsub(/\[!\[.*?\]\(.*?\)\]/, "")
                    .gsub(/\[([^\]]+)\]\([^)]+\)/, '\1')
                    .strip
        clean.empty? ? humanize_filename(filename) : clean
      end

      def humanize_filename(filename)
        File.basename(filename, File.extname(filename))
          .tr("-_", " ")
          .gsub(/\b\w/, &:upcase)
      end

      def extract_headings(content)
        content.scan(/^\#{2,4}\s+(.+)$/).flatten.map(&:strip)
      end

      # --- Version extraction ---

      # Extract a meaningful version string from the branch name or repo tags.
      # Examples: "v8.1.2" → "8.1.2", "main" → nil, "release/3.0" → "3.0"
      def extract_version(branch, repo_data)
        return nil unless branch

        # Strip common prefixes: v1.0.0, release/1.0.0
        cleaned = branch.sub(/\Av/i, "").sub(%r{\Arelease/}i, "")

        # Only use it if it looks like a version (starts with a digit)
        cleaned.match?(/\A\d/) ? cleaned : nil
      end

      # --- Result building ---

      def build_result(owner, repo, repo_data, pages, version = nil)
        display_name = repo_data["name"]&.tr("-", " ")&.gsub(/\b\w/, &:upcase) ||
                       repo.tr("-", " ").split.map(&:capitalize).join(" ")
        description = repo_data["description"]

        # Use topics + repo name for aliases
        topics = repo_data["topics"] || []
        aliases = ([ repo, repo.tr("-", "") ] + topics.first(5)).uniq

        Result.new(
          namespace: owner.downcase,
          name: repo.downcase,
          display_name: display_name,
          homepage_url: repo_data["homepage"].presence || "https://github.com/#{owner}/#{repo}",
          aliases: aliases,
          version: version,
          pages: pages
        )
      end

      # --- HTTP ---

      def github_api_get(path)
        uri = URI("#{GITHUB_API}#{path}")
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/vnd.github.v3+json"
        request["User-Agent"] = "ContextQMD-Registry/1.0"
        token = Rails.application.credentials.dig(:github, :token)
        request["Authorization"] = "token #{token}" if token

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true,
          open_timeout: 10, read_timeout: 30) do |http|
          http.request(request)
        end

        raise "GitHub API error #{response.code}: #{response.body.first(200)}" unless response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
      end

      def raw_get(owner, repo, branch, path)
        uri = URI("#{RAW_BASE}/#{owner}/#{repo}/#{branch}/#{URI::DEFAULT_PARSER.escape(path)}")
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = "ContextQMD-Registry/1.0"

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true,
          open_timeout: 10, read_timeout: 15) do |http|
          http.request(request)
        end

        return nil unless response.is_a?(Net::HTTPSuccess)
        response.body.force_encoding("UTF-8")
      end
  end
end
