# frozen_string_literal: true

require "find"
require "json"
require "open3"
require "tmpdir"

module DocsFetcher
  # Base class for git-based doc fetchers. Uses `git clone --depth 1`.
  # Host-specific subclasses (GitHub, GitLab, Bitbucket) override URL parsing.
  # Also serves as the fallback for unknown git hosts (source_type="git").
  class Git
    DOC_EXTENSIONS = %w[.md .mdx .html .rst .ipynb].freeze

    # Default directory prefixes to exclude (relative path segments).
    # Per-library config adds to these (union). Include prefixes override excludes.
    DEFAULT_EXCLUDE_PREFIXES = %w[
      dist build out _build _site .next .nuxt target
      vendor node_modules .bundle bower_components
      .github .gitlab .circleci .husky .devcontainer .vscode .claude .codex
      test tests spec specs __tests__ __mocks__ fixtures testdata
      archive archived deprecated legacy obsolete outdated superseded old previous
      examples example demo demos sample samples
      i18n l10n locales translations zh-cn zh-tw zh-hk zh-mo zh-sg
    ].freeze

    # Default basenames to exclude (matched against filename only).
    DEFAULT_EXCLUDE_BASENAMES = %w[
      CHANGELOG.md changelog.md CHANGELOG.mdx changelog.mdx
      LICENSE.md license.md LICENSE.txt license.txt
      CODE_OF_CONDUCT.md code_of_conduct.md
      CONTRIBUTING.md contributing.md
      SECURITY.md security.md
      NEWS.md
    ].freeze

    def fetch(crawl_request, on_progress: nil)
      url = crawl_request.url
      repo_url = normalize_git_url(url)
      explicit_ref = extract_branch_from_url(url)
      branch_or_tag = explicit_ref.presence || resolve_latest_tag(repo_url)
      @crawl_rules = load_crawl_rules(crawl_request)

      Dir.mktmpdir("contextqmd-git-") do |tmpdir|
        on_progress&.call("Cloning repository")
        clone!(repo_url, tmpdir, branch_or_tag: branch_or_tag)

        files = discover_doc_files(tmpdir)
        raise DocsFetcher::PermanentFetchError, "No documentation found in #{repo_url}" if files.empty?

        on_progress&.call("Discovered #{files.size} doc files")
        pages = build_pages(files, tmpdir, url, branch_or_tag)
        raise DocsFetcher::PermanentFetchError, "No documentation content fetched from #{repo_url}" if pages.empty?

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
        raise DocsFetcher::TransientFetchError, "git clone failed for #{repo_url}" unless success
      end

      # --- URL parsing (template methods — override in subclasses) ---

      def normalize_git_url(url)
        uri = URI.parse(url.strip)
        clean_path = uri.path.to_s.delete_prefix("/").delete_suffix(".git")
        "https://#{uri.host&.downcase}/#{clean_path}.git"
      end

      def extract_branch_from_url(_url)
        nil
      end

      def extract_owner_repo(url)
        uri = URI.parse(url.strip)
        parts = uri.path.delete_prefix("/").split("/")
        owner = parts[0]
        repo_name = parts[1]&.delete_suffix(".git")
        raise ArgumentError, "Invalid git URL: #{url}" unless owner.present? && repo_name.present?
        [ owner.downcase, repo_name.downcase ]
      end

      def build_file_url(source_url, rel_path, branch_or_tag)
        uri = URI.parse(source_url.strip)
        parts = uri.path.delete_prefix("/").split("/")
        ref = branch_or_tag || "main"
        "#{uri.scheme}://#{uri.host&.downcase}/#{parts.first(2).join('/')}/blob/#{ref}/#{rel_path}"
      end

      def normalize_homepage_url(source_url)
        source_url.strip
      end

      # --- Crawl rules ---

      def load_crawl_rules(crawl_request)
        return {} unless crawl_request.library_id.present?

        crawl_request.library&.crawl_rules || {}
      end

      def effective_exclude_prefixes
        rules = @crawl_rules || {}
        DEFAULT_EXCLUDE_PREFIXES + Array(rules["git_exclude_prefixes"])
      end

      def effective_exclude_basenames
        rules = @crawl_rules || {}
        DEFAULT_EXCLUDE_BASENAMES + Array(rules["git_exclude_basenames"])
      end

      def effective_include_prefixes
        rules = @crawl_rules || {}
        Array(rules["git_include_prefixes"])
      end

      # --- File discovery ---

      # Uses Find.find + Find.prune to skip excluded directories entirely
      # (not scanned then post-filtered). This matters for large repos with
      # deep node_modules or vendor trees.
      def discover_doc_files(tmpdir)
        exclude_prefixes = effective_exclude_prefixes.map(&:downcase)
        exclude_basenames = Set.new(effective_exclude_basenames)
        include_prefixes = effective_include_prefixes.map(&:downcase)

        files = []
        Find.find(tmpdir) do |path|
          rel = path.sub("#{tmpdir}/", "")

          # Prune excluded directories early
          if File.directory?(path) && path != tmpdir
            dirname = File.basename(path).downcase
            rel_lower = rel.downcase

            # .git is always pruned
            if dirname == ".git"
              Find.prune
              next
            end

            # Check if directory matches an include prefix (overrides excludes)
            unless include_prefixes.any? { |ip| rel_lower.start_with?(ip) || ip.start_with?(rel_lower) }
              # Check if any path segment matches an exclude prefix
              if exclude_prefixes.include?(dirname) ||
                 exclude_prefixes.any? { |ep| rel_lower.start_with?(ep) || rel_lower.start_with?("#{ep}/") }
                Find.prune
                next
              end
            end

            next
          end

          next unless File.file?(path)
          next unless File.size(path) > 0
          next unless DOC_EXTENSIONS.include?(File.extname(path).downcase)

          basename = File.basename(path)
          next if exclude_basenames.include?(basename)

          # Include prefixes override basename excludes too
          rel_lower = rel.downcase
          if include_prefixes.any? { |ip| rel_lower.start_with?(ip) }
            files << path
            next
          end

          files << path
        end

        files
      end

      # --- Page building ---

      def build_pages(files, tmpdir, source_url, branch_or_tag)
        files.filter_map do |full_path|
          rel = full_path.sub("#{tmpdir}/", "")
          raw_content = File.read(full_path, encoding: "UTF-8")
          next if raw_content.strip.empty?

          ext = File.extname(full_path).downcase
          content, extra_title = convert_content(raw_content, ext)
          next if content.nil? || content.strip.empty?

          title = extra_title || extract_title(content, rel)
          content = strip_frontmatter(content) if ext == ".md" || ext == ".mdx"
          headings = content.scan(/^\#{2,4}\s+(.+)$/).flatten.map(&:strip)
          slug = rel.delete_suffix(File.extname(rel)).tr("/", "-").downcase

          {
            page_uid: slug,
            path: rel,
            title: title,
            url: build_file_url(source_url, rel, branch_or_tag),
            content: content,
            headings: headings
          }
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

            lang = notebook.dig("metadata", "kernelspec", "language") ||
                   notebook.dig("metadata", "language_info", "name") || ""
            "```#{lang}\n#{source}\n```"
          end
        end

        [ parts.join("\n\n"), nil ]
      rescue JSON::ParserError => e
        Rails.logger.warn("Failed to parse .ipynb: #{e.message}")
        [ nil, nil ]
      end

      # --- Content extraction ---

      INSTRUCTION_PREFIXES = /\A(use |you should|if you|install |run |make sure|please |note:|ensure |do not )/i

      def extract_title(content, filename)
        if content.start_with?("---")
          fm = content.split("---", 3)[1]
          if fm && (match = fm.match(/^title:\s*["']?(.+?)["']?\s*$/))
            return clean_title(match[1], filename)
          end
        end

        content.lines.first(30).each do |line|
          next unless (match = line.match(/^#\s+(.+)$/))
          title = clean_title(match[1], filename)
          next if title.match?(INSTRUCTION_PREFIXES)
          return title
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

      def resolve_latest_tag(repo_url)
        stable_candidates = []
        prerelease_candidates = []

        list_remote_tags(repo_url).each do |tag|
          version = extract_version(tag)
          next unless version

          parsed = Version.parse(version)
          next unless parsed

          candidate = { ref: tag, parsed: parsed }
          if Version.channel_for(version) == "stable"
            stable_candidates << candidate
          else
            prerelease_candidates << candidate
          end
        end

        select_highest_tag(stable_candidates) || select_highest_tag(prerelease_candidates)
      end

      def list_remote_tags(repo_url)
        output, status = Open3.capture2("git", "ls-remote", "--tags", "--refs", repo_url)
        unless status.success?
          Rails.logger.warn("git ls-remote failed for #{repo_url}")
          return []
        end

        output.lines.filter_map do |line|
          _sha, ref = line.split("\t", 2)
          next unless ref&.start_with?("refs/tags/")

          ref.strip.delete_prefix("refs/tags/")
        end
      rescue StandardError => e
        Rails.logger.warn("Failed to list remote tags for #{repo_url}: #{e.message}")
        []
      end

      def select_highest_tag(candidates)
        candidates.max_by { |candidate| candidate[:parsed] }&.dig(:ref)
      end

      # --- Result building ---

      def build_result(owner, repo_name, source_url, pages, version)
        display_name = repo_name.tr("-", " ").split.map(&:capitalize).join(" ")
        aliases = [ repo_name, repo_name.tr("-", ""), repo_name.tr(".", "-") ].map(&:downcase).uniq

        CrawlResult.new(
          namespace: owner,
          name: repo_name,
          display_name: display_name,
          homepage_url: normalize_homepage_url(source_url),
          aliases: aliases,
          version: version,
          pages: pages
        )
      end
  end
end
