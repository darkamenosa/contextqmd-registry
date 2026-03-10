# frozen_string_literal: true

require "json"
require "tmpdir"

module DocsFetcher
  # Fetches documentation from any git repository using `git clone --depth 1`.
  # Replaces the separate Github and Gitlab fetchers with a unified approach
  # that works with GitHub, GitLab, Bitbucket, and any git-accessible repo.
  #
  # Strategy:
  # 1. Shallow clone the repo into a tmpdir
  # 2. Walk the filesystem to discover doc files (.md, .mdx, .html, .rst, .ipynb)
  # 3. Score and rank files by documentation relevance
  # 4. Read content from disk (no API calls needed)
  # 5. Convert non-markdown formats (.html, .ipynb) to markdown
  # 6. Return structured Result
  class Git
    MAX_PAGES = 500
    MAX_FILE_SIZE = 500_000       # 500KB per file
    MAX_TOTAL_BYTES = 20_000_000  # 20MB total content budget
    CLONE_TIMEOUT = 120           # seconds

    DOC_EXTENSIONS = %w[.md .mdx .html .rst .ipynb].freeze

    # Directories that almost always contain documentation
    HIGH_VALUE_DIRS = %w[
      docs doc documentation guide guides guides/source
      content content/docs content/guide
      website/docs website/content
      pages/docs manual reference wiki
    ].freeze

    # Directories to always skip
    SKIP_DIRS = %w[
      archive archived old obsolete deprecated legacy previous outdated superseded
      test tests spec __tests__ fixtures __fixtures__ benchmark benchmarks
      .github .git node_modules vendor
      dist build out target _build coverage .cache
      __pycache__ .next .nuxt
      examples/node_modules
    ].freeze

    # Multi-segment directory patterns to skip
    SKIP_DIR_PATTERNS = %w[
      lib/cjs lib/esm lib/umd lib/es lib/dist lib/build
      lib/out lib/output lib/js lib/ts lib/src lib/pkg
    ].freeze

    # Locale directories to skip (non-English content)
    SKIP_LOCALE_DIRS = %w[zh-cn zh-tw zh-hk zh-mo zh-sg].freeze

    # Files that are NOT documentation (even if they're markdown)
    SKIP_FILES = %w[
      CHANGELOG.md CHANGES.md HISTORY.md changelog.md changelog.mdx
      LICENSE.md LICENSE-MIT.md LICENSE-APACHE.md license.md
      CODE_OF_CONDUCT.md code_of_conduct.md SECURITY.md
      CODEOWNERS CONTRIBUTING.md RELEASING.md
      NEWS.md
    ].freeze

    # Root-level files worth including alongside docs
    ROOT_DOC_FILES = %w[
      README.md UPGRADING.md MIGRATION.md
      GETTING_STARTED.md QUICKSTART.md
      ARCHITECTURE.md DESIGN.md
    ].freeze

    def fetch(url)
      repo_url = normalize_git_url(url)
      branch_or_tag = extract_branch_from_url(url)

      Dir.mktmpdir("contextqmd-git-") do |tmpdir|
        clone!(repo_url, tmpdir, branch_or_tag: branch_or_tag)
        head_sha = read_head_sha(tmpdir)

        candidates = discover_doc_files(tmpdir)
        raise "No documentation found in #{repo_url}" if candidates.empty?

        ranked = score_and_rank(candidates, tmpdir)
        pages = build_pages(ranked, tmpdir, url, branch_or_tag)
        raise "No documentation content fetched from #{repo_url}" if pages.empty?

        owner, repo_name = extract_owner_repo(url)
        version = extract_version(branch_or_tag)

        build_result(owner, repo_name, url, pages, version)
      end
    end

    private

      # --- Git operations ---

      def clone!(repo_url, tmpdir, branch_or_tag: nil)
        args = [ "git", "clone", "--depth", "1", "--single-branch" ]
        args += [ "--branch", branch_or_tag ] if branch_or_tag.present?
        args += [ repo_url, tmpdir ]

        success = system(*args, out: File::NULL, err: File::NULL)
        raise "git clone failed for #{repo_url}" unless success
      end

      def read_head_sha(tmpdir)
        head_file = File.join(tmpdir, ".git", "HEAD")
        return nil unless File.exist?(head_file)

        ref = File.read(head_file).strip
        if ref.start_with?("ref: ")
          ref_path = File.join(tmpdir, ".git", ref.sub("ref: ", ""))
          File.exist?(ref_path) ? File.read(ref_path).strip : nil
        else
          ref # detached HEAD — already a SHA
        end
      end

      # --- URL parsing ---

      def normalize_git_url(url)
        uri = URI.parse(url.strip)
        host = uri.host&.downcase || ""
        path = uri.path || ""

        # Strip tree/branch/blob paths for GitHub/GitLab/Bitbucket
        # e.g., /rails/rails/tree/v8.1.2 → /rails/rails
        parts = path.delete_prefix("/").split("/")

        if github_host?(host)
          # GitHub: owner/repo[/tree|blob/...]
          clean_parts = parts.first(2)
        elsif gitlab_host?(host)
          # GitLab: group[/subgroup]/project[/-/tree/...]
          separator_idx = parts.index("-")
          clean_parts = separator_idx ? parts[0...separator_idx] : parts
        elsif bitbucket_host?(host)
          # Bitbucket: owner/repo[/src/...]
          clean_parts = parts.first(2)
        else
          clean_parts = parts
        end

        clean_path = clean_parts.join("/").delete_suffix(".git")
        "https://#{host}/#{clean_path}.git"
      end

      def extract_branch_from_url(url)
        uri = URI.parse(url.strip)
        host = uri.host&.downcase || ""
        parts = uri.path.delete_prefix("/").split("/")

        if github_host?(host)
          # /owner/repo/tree/branch-name
          parts[3] if parts[2] == "tree"
        elsif gitlab_host?(host)
          # /group/project/-/tree/branch-name
          separator_idx = parts.index("-")
          if separator_idx && parts[separator_idx + 1] == "tree"
            parts[separator_idx + 2]
          end
        elsif bitbucket_host?(host)
          # /owner/repo/src/branch-name
          parts[3] if parts[2] == "src"
        end
      rescue URI::InvalidURIError
        nil
      end

      def extract_owner_repo(url)
        uri = URI.parse(url.strip)
        parts = uri.path.delete_prefix("/").split("/")

        if gitlab_host?(uri.host&.downcase || "")
          separator_idx = parts.index("-")
          project_parts = separator_idx ? parts[0...separator_idx] : parts
          owner = project_parts[0...-1].join("/")
          repo_name = project_parts.last
        else
          owner = parts[0]
          repo_name = parts[1]
        end

        repo_name = repo_name&.delete_suffix(".git")
        raise ArgumentError, "Invalid git URL: #{url}" unless owner.present? && repo_name.present?

        [ owner.downcase, repo_name.downcase ]
      end

      def github_host?(host)
        host == "github.com"
      end

      def gitlab_host?(host)
        host == "gitlab.com" || host.include?("gitlab")
      end

      def bitbucket_host?(host)
        host == "bitbucket.org"
      end

      # --- File discovery ---

      def discover_doc_files(tmpdir)
        Dir.glob(File.join(tmpdir, "**", "*")).select do |path|
          next false if path.include?("/.git/")

          ext = File.extname(path).downcase
          rel = relative_path(path, tmpdir)

          DOC_EXTENSIONS.include?(ext) &&
            !skip_path?(rel) &&
            File.file?(path) &&
            File.size(path) > 0 &&
            File.size(path) < MAX_FILE_SIZE
        end
      end

      def relative_path(full_path, tmpdir)
        full_path.sub("#{tmpdir}/", "")
      end

      def skip_path?(path)
        parts = path.split("/")
        dir_path = parts[0...-1].join("/").downcase

        # Skip files in excluded directories
        return true if SKIP_DIRS.any? { |d|
          if d.include?("/")
            dir_path.start_with?(d) || dir_path.include?("/#{d}")
          else
            parts.any? { |p| p.downcase == d }
          end
        }

        # Skip multi-segment dir patterns
        return true if SKIP_DIR_PATTERNS.any? { |pattern|
          dir_path.start_with?(pattern) || dir_path.include?("/#{pattern}")
        }

        # Skip locale directories
        return true if SKIP_LOCALE_DIRS.any? { |locale|
          parts.any? { |p| p.downcase == locale }
        }

        # Skip blacklisted filenames (case-insensitive)
        filename = parts.last
        return true if SKIP_FILES.any? { |f| filename.casecmp(f).zero? }

        false
      end

      # --- Scoring ---

      def score_and_rank(candidates, tmpdir)
        scored = candidates.map do |full_path|
          rel = relative_path(full_path, tmpdir)
          size = File.size(full_path)
          { path: full_path, rel: rel, score: score_file(rel, size) }
        end

        scored
          .sort_by { |s| -s[:score] }
          .first(MAX_PAGES)
      end

      def score_file(path, size)
        score = 0.0
        parts = path.split("/")
        filename = parts.last
        dir_path = parts[0...-1].join("/").downcase

        # Root-level documentation files
        if parts.length == 1
          if ROOT_DOC_FILES.any? { |f| filename.casecmp(f).zero? }
            score += 100
          elsif filename.casecmp("README.md").zero?
            score += 80
          end
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

        # Size signal: very small files (<500b) are likely stubs
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

      # --- Page building ---

      def build_pages(ranked, tmpdir, source_url, branch_or_tag)
        pages = []
        total_bytes = 0
        host = URI.parse(source_url.strip).host&.downcase || ""

        ranked.each do |entry|
          break if total_bytes >= MAX_TOTAL_BYTES

          full_path = entry[:path]
          rel = entry[:rel]
          raw_content = File.read(full_path, encoding: "UTF-8")
          next if raw_content.strip.empty?

          # Convert non-markdown formats
          ext = File.extname(full_path).downcase
          content, extra_title = convert_content(raw_content, ext)
          next if content.nil? || content.strip.empty?

          total_bytes += content.bytesize
          break if total_bytes > MAX_TOTAL_BYTES && pages.any?

          title = extra_title || extract_title(content, rel)
          content = strip_frontmatter(content) if ext == ".md" || ext == ".mdx"
          headings = extract_headings(content)
          slug = rel.delete_suffix(File.extname(rel)).tr("/", "-").downcase

          page_url = build_file_url(source_url, host, rel, branch_or_tag)

          pages << {
            page_uid: slug,
            path: rel,
            title: title,
            url: page_url,
            content: content,
            headings: headings
          }
        end

        pages
      end

      def build_file_url(source_url, host, rel_path, branch_or_tag)
        uri = URI.parse(source_url.strip)
        parts = uri.path.delete_prefix("/").split("/")
        ref = branch_or_tag || "main"

        if github_host?(host)
          owner = parts[0]
          repo = parts[1]&.delete_suffix(".git")
          "https://github.com/#{owner}/#{repo}/blob/#{ref}/#{rel_path}"
        elsif gitlab_host?(host)
          separator_idx = parts.index("-")
          project_parts = separator_idx ? parts[0...separator_idx] : parts
          project_path = project_parts.join("/")
          "https://#{host}/#{project_path}/-/blob/#{ref}/#{rel_path}"
        elsif bitbucket_host?(host)
          owner = parts[0]
          repo = parts[1]&.delete_suffix(".git")
          "https://bitbucket.org/#{owner}/#{repo}/src/#{ref}/#{rel_path}"
        else
          "#{uri.scheme}://#{host}/#{parts.first(2).join('/')}/blob/#{ref}/#{rel_path}"
        end
      end

      # --- Content conversion ---

      def convert_content(raw_content, ext)
        case ext
        when ".md", ".mdx"
          [ raw_content, nil ]
        when ".html"
          result = HtmlToMarkdown.convert(raw_content)
          [ result[:content], result[:title] ]
        when ".ipynb"
          convert_ipynb(raw_content)
        when ".rst"
          # Read as-is for now — plain text is still useful
          [ raw_content, nil ]
        else
          [ raw_content, nil ]
        end
      rescue StandardError => e
        Rails.logger.warn("Failed to convert #{ext} content: #{e.message}")
        nil
      end

      def convert_ipynb(raw_content)
        notebook = JSON.parse(raw_content)
        cells = notebook["cells"] || []

        parts = cells.filter_map do |cell|
          case cell["cell_type"]
          when "markdown"
            source = Array(cell["source"]).join
            source.strip.empty? ? nil : source
          when "code"
            source = Array(cell["source"]).join
            next nil if source.strip.empty?

            # Detect language from notebook metadata
            lang = notebook.dig("metadata", "kernelspec", "language") ||
                   notebook.dig("metadata", "language_info", "name") || ""

            "```#{lang}\n#{source}\n```"
          end
        end

        content = parts.join("\n\n")
        [ content, nil ]
      rescue JSON::ParserError => e
        Rails.logger.warn("Failed to parse .ipynb: #{e.message}")
        [ nil, nil ]
      end

      # --- Content extraction ---

      INSTRUCTION_PREFIXES = /\A(use |you should|if you|install |run |make sure|please |note:|ensure |do not )/i

      def extract_title(content, filename)
        # Try frontmatter title first
        if content.start_with?("---")
          fm = content.split("---", 3)[1]
          if fm && (match = fm.match(/^title:\s*["']?(.+?)["']?\s*$/))
            return clean_title(match[1], filename)
          end
        end

        # Look only in the first 30 lines
        header_lines = content.lines.first(30)

        # Try ATX-style headings, skipping instruction-like ones
        header_lines.each do |line|
          next unless (match = line.match(/^#\s+(.+)$/))
          title = clean_title(match[1], filename)
          next if title.match?(INSTRUCTION_PREFIXES)
          return title
        end

        # Try Setext-style: Title\n====
        header_region = header_lines.join
        if (match = header_region.match(/^([^\n#*`<>]{3,})\n={3,}\s*$/))
          title = clean_title(match[1], filename)
          return title unless title.match?(INSTRUCTION_PREFIXES)
        end

        humanize_filename(filename)
      end

      def clean_title(raw, filename)
        clean = raw.gsub(/<[^>]+>/, "")
                    .gsub(/\[!\[.*?\]\(.*?\)\]/, "")
                    .gsub(/\[([^\]]+)\]\([^)]+\)/, '\1')
                    .gsub("\\", "")
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

      def strip_frontmatter(content)
        return content unless content.start_with?("---")

        parts = content.split("---", 3)
        parts.length >= 3 ? parts[2].lstrip : content
      end

      # --- Version extraction ---

      def extract_version(branch)
        return nil unless branch

        cleaned = branch.sub(/\Av/i, "").sub(%r{\Arelease/}i, "")
        cleaned.match?(/\A\d/) ? cleaned : nil
      end

      # --- Result building ---

      def build_result(owner, repo_name, source_url, pages, version)
        display_name = repo_name.tr("-", " ").split.map(&:capitalize).join(" ")
        aliases = [ repo_name, repo_name.tr("-", ""), repo_name.tr(".", "-") ].map(&:downcase).uniq

        homepage_url = source_url.strip
        # Clean up tree/branch paths from homepage URL
        uri = URI.parse(homepage_url)
        host = uri.host&.downcase || ""
        parts = uri.path.delete_prefix("/").split("/")
        if github_host?(host)
          homepage_url = "https://github.com/#{parts.first(2).join('/')}"
        elsif bitbucket_host?(host)
          homepage_url = "https://bitbucket.org/#{parts.first(2).join('/')}"
        end

        Result.new(
          namespace: owner,
          name: repo_name,
          display_name: display_name,
          homepage_url: homepage_url,
          aliases: aliases,
          version: version,
          pages: pages
        )
      end
  end
end
