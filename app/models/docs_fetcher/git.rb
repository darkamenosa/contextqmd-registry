# frozen_string_literal: true

require "find"
require "json"
require "nokogiri"
require "open3"
require "set"
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
      .changeset .changesets .factory .cloudflare
      test tests spec specs __tests__ __mocks__ fixtures testdata
      archive archived deprecated legacy obsolete outdated superseded old previous
      demo demos sample samples
      integration-tests benchmarks bench perf evals
      legal nix
      i18n l10n locales translations i18n-guides
      ar bg bn cs da de el es et fa fi fr he hi hr hu id it ja ka kk km
      ko lt lv mk mn ms my nl no pl pt ro ru sk sl sq sr sv sw ta te th
      tl tr uk ur vi zh
      pt-br zh-cn zh-tw zh-hk zh-mo zh-sg ja-jp ko-kr
    ].freeze

    # Default basenames to exclude (matched against filename only).
    DEFAULT_EXCLUDE_BASENAMES = %w[
      CHANGELOG.md changelog.md CHANGELOG.mdx changelog.mdx
      LICENSE.md license.md LICENSE.txt license.txt
      CODE_OF_CONDUCT.md code_of_conduct.md
      CONTRIBUTING.md contributing.md
      SECURITY.md security.md
      NEWS.md
      CLAUDE.md AGENTS.md GEMINI.md
    ].freeze

    def fetch(crawl_request, on_progress: nil)
      url = crawl_request.url
      repo_url = normalize_git_url(url)
      explicit_ref = extract_branch_from_url(url)
      @crawl_rules = load_crawl_rules(crawl_request)

      # Always clone the default branch for docs content — docs on main/master
      # represent the latest state. Resolve the latest tag separately for
      # version labeling only. If the user specified an explicit ref (e.g.
      # /tree/v2.0), honour that for both content and version.
      resolved_tag = explicit_ref.presence || resolve_latest_tag(repo_url)
      clone_ref = explicit_ref # nil = default branch; explicit ref = user's choice

      Dir.mktmpdir("contextqmd-git-") do |tmpdir|
        on_progress&.call("Cloning repository")
        clone_repository(repo_url, tmpdir, branch_or_tag: clone_ref)

        branch_or_tag = clone_ref || detect_head_branch(tmpdir)

        files = discover_doc_files(tmpdir)
        raise DocsFetcher::PermanentFetchError, "No documentation found in #{repo_url}" if files.empty?

        on_progress&.call("Discovered #{files.size} doc files")
        pages = build_pages(files, tmpdir, url, branch_or_tag)
        raise DocsFetcher::PermanentFetchError, "No documentation content fetched from #{repo_url}" if pages.empty?

        owner, repo_name = extract_owner_repo(url)
        # When cloning an explicit ref, use that as the version.
        # When cloning HEAD (clone_ref is nil), label as "latest" — the content
        # is from the default branch, not from the resolved tag.
        version = if clone_ref
          extract_version(clone_ref)
        else
          extract_version(resolved_tag) || "latest"
        end

        build_result(owner, repo_name, url, pages, version)
      end
    end

    private

      # --- Git operations ---

      def clone_repository(repo_url, tmpdir, branch_or_tag: nil)
        args = [ "git", "clone", "--depth", "1", "--single-branch" ]
        args += [ "--branch", branch_or_tag ] if branch_or_tag.present?
        args += [ repo_url, tmpdir ]

        success = system(*args, out: File::NULL, err: File::NULL)
        raise DocsFetcher::TransientFetchError, "git clone failed for #{repo_url}" unless success
      end

      def detect_head_branch(tmpdir)
        output, status = Open3.capture2("git", "-C", tmpdir, "rev-parse", "--abbrev-ref", "HEAD")
        return nil unless status.success?

        branch = output.strip
        # "HEAD" means detached state (tag checkout) — not a usable branch name
        branch == "HEAD" ? nil : branch.presence
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

      def effective_include_basenames
        rules = @crawl_rules || {}
        Set.new(Array(rules["git_include_basenames"]))
      end

      # --- File discovery ---

      # Uses Find.find + Find.prune to skip excluded directories entirely
      # (not scanned then post-filtered). This matters for large repos with
      # deep node_modules or vendor trees.
      def discover_doc_files(tmpdir)
        exclude_prefixes = effective_exclude_prefixes.map(&:downcase)
        exclude_basenames = Set.new(effective_exclude_basenames)
        include_prefixes = effective_include_prefixes.map(&:downcase)
        include_basenames = effective_include_basenames

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
              # Check directory basename OR root-relative prefix against excludes
              if exclude_prefixes.include?(dirname) ||
                 exclude_prefixes.any? { |ep| rel_lower == ep || rel_lower.start_with?("#{ep}/") }
                Find.prune
                next
              end
            end

            next
          end

          next unless File.file?(path)
          file_size = File.size(path)
          next unless file_size > 0
          next if file_size > 5_000_000 # Skip files > 5MB (auto-generated dumps)
          next unless DOC_EXTENSIONS.include?(File.extname(path).downcase)

          basename = File.basename(path)
          next if exclude_basenames.include?(basename) && !include_basenames.include?(basename)

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
        used_page_uids = Set.new

        files.filter_map do |full_path|
          rel = full_path.sub("#{tmpdir}/", "")
          ext = File.extname(full_path).downcase
          raw_content = read_text_file(full_path)
          next if raw_content.blank?

          content, extra_title = convert_content(raw_content, ext)
          next if content.nil? || content.strip.empty?

          title = extra_title.presence || extract_title(content, rel)
          title = humanize_filename(rel) if title.blank?
          title = File.basename(rel, File.extname(rel)) if title.blank?
          title = "Untitled" if title.blank?
          content = strip_frontmatter(content) if ext == ".md" || ext == ".mdx"
          next if content.strip.empty?

          headings = if ext == ".rst"
            extract_rst_headings(content, title)
          else
            content.scan(/^\#{2,4}\s+(.+)$/).flatten.map(&:strip)
          end

          {
            page_uid: unique_page_uid(rel, ext, used_page_uids),
            path: rel,
            title: title,
            url: build_file_url(source_url, rel, branch_or_tag),
            content: content,
            headings: headings
          }
        end
      end

      def read_text_file(full_path)
        content = File.binread(full_path).force_encoding(Encoding::UTF_8).scrub("")
        content.delete_prefix!("\xEF\xBB\xBF")
        content
      end

      def unique_page_uid(rel, ext, used_page_uids)
        base = rel.delete_suffix(ext).tr("\\", "/")
        candidate = base

        if used_page_uids.include?(candidate)
          ext_suffix = ext.delete_prefix(".").parameterize(separator: "-")
          ext_candidate = "#{base}-#{ext_suffix}"
          candidate = ext_candidate unless ext_suffix.blank? || used_page_uids.include?(ext_candidate)
        end

        suffix = 2
        while used_page_uids.include?(candidate)
          candidate = "#{base}-#{suffix}"
          suffix += 1
        end

        used_page_uids << candidate
        candidate
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
          [ raw_content, extract_rst_title(raw_content) ]
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

      # --- RST title extraction ---

      # RST headings use underline (and optional overline) with characters like = - ~ ^ "
      # Example: "fish - the friendly interactive shell\n====================================="
      RST_UNDERLINE_CHARS = %r{\A[=\-~^"+#*`.':!_]{3,}\z}

      def extract_rst_title(content)
        lines = content.lines.map(&:rstrip)
        lines.each_with_index do |line, i|
          next_line = lines[i + 1]
          next unless next_line&.match?(RST_UNDERLINE_CHARS)
          next unless next_line.length >= line.length

          # Skip if line is blank, a directive, or itself an underline
          title = line.strip
          next if title.empty?
          next if title.start_with?("..")
          next if title.match?(RST_UNDERLINE_CHARS)

          # Strip RST inline markup from the title (links like `text <url>`_ or `text <url>`__)
          title = title.gsub(/`([^<`]+)\s*<[^>]+>`_{1,2}/, '\1').strip
          # Strip RST role-like badges (|Build Status| etc.)
          title = title.gsub(/\|[^|]+\|/, "").strip
          # Clean up leftover whitespace and punctuation artifacts
          title = title.squish
          return title if title.present?
        end

        nil
      end

      # Extract sub-headings (not the title) from RST content.
      # Skips the heading that matches the page title, keeps all others.
      # Strips RST role markup from heading text.
      def extract_rst_headings(content, page_title)
        headings = []
        lines = content.lines.map(&:rstrip)

        lines.each_with_index do |line, i|
          next_line = lines[i + 1]
          next unless next_line&.match?(RST_UNDERLINE_CHARS)
          next unless next_line.length >= line.length

          heading = line.strip
          next if heading.empty? || heading.start_with?("..") || heading.match?(RST_UNDERLINE_CHARS)

          # Clean RST role markup: :doc:`ref` → ref, :mod:`name` → name
          heading = clean_rst_heading(heading)
          next if heading.blank?

          # Skip the heading that matches the extracted page title
          next if page_title.present? && heading == page_title

          headings << heading
        end

        headings
      end

      # Strip RST inline roles and markup from heading text.
      def clean_rst_heading(text)
        text
          .gsub(/:[a-z]+:`([^`]+)`/, '\1')  # :doc:`ref` → ref, :mod:`name` → name
          .gsub(/`([^<`]+)\s*<[^>]+>`_{1,2}/, '\1')  # `text <url>`_ → text
          .gsub(/\|[^|]+\|/, "")             # |substitution| → remove
          .squish
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
                    .gsub(/\[\!\[[^\]]*\]\((?:[^()]|\([^)]*\))*\)\]\((?:[^()]|\([^)]*\))*\)/, "")
                    .gsub(/\!\[[^\]]*\]\((?:[^()]|\([^)]*\))*\)/, "")
                    .gsub(/\[([^\]]+)\]\((?:[^()]|\([^)]*\))*\)/, '\1')
        clean = Nokogiri::HTML.fragment(clean).text
                    .gsub("\\", "")
                    .squish
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
          next if absurd_version?(version)

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

      # Reject versions with absurdly high numeric components (test tags,
      # build numbers, commit-hash dates, etc.).
      # Examples rejected: "0.999999.0", "999.9.9", "54011", "2234",
      #                    "20240203-110809-5046fc22", "2024.1.300751-latest"
      # Examples allowed:  "3.14.2", "2026.3.1", "16.1.6", "0.135.1"
      def absurd_version?(version)
        segments = version.split(/[.\-]/)
        numeric_segments = segments.filter_map { |s| s.to_i if s.match?(/\A\d+\z/) }
        return false if numeric_segments.empty?

        # Any segment >= 9999 is always absurd (e.g. 999999, 9999, 300751, 54011)
        return true if numeric_segments.any? { |n| n >= 9999 }

        # Leading segment > 999 is absurd unless it's a plausible year (2000–2099)
        first = numeric_segments.first
        return true if first > 999 && !(first >= 2000 && first <= 2099)

        # Multiple 9s pattern: major version of exactly 999 (test placeholder)
        return true if first == 999

        false
      end

      def select_highest_tag(candidates)
        candidates.max_by { |candidate| candidate[:parsed] }&.dig(:ref)
      end

      # --- Result building ---

      def build_result(owner, repo_name, source_url, pages, version)
        identity = LibraryIdentity.from_git(
          owner: owner,
          repo_name: repo_name,
          source_url: source_url
        )

        CrawlResult.new(
          slug: identity[:slug],
          namespace: identity[:namespace],
          name: identity[:name],
          display_name: identity[:display_name],
          homepage_url: normalize_homepage_url(source_url),
          aliases: identity[:aliases],
          version: version,
          pages: pages
        )
      end
  end
end
