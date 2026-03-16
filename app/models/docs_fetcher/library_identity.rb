# frozen_string_literal: true

module DocsFetcher
  module LibraryIdentity
    GENERIC_SOURCE_NAMES = %w[
      api book doc docs documentation guide guides handbook manual manuals
      reference references site website wiki
      core app client server sdk framework runtime engine lib utils tools
      cli ui web js
    ].freeze

    # Suffixes on repo names that indicate a docs/website repo rather than the
    # actual project repo. Stripped to derive the product slug.
    # e.g. "docs.nestjs.com" → "nestjs", "kamal-site" → "kamal"
    # Only TLDs that are overwhelmingly used for docs websites, not product names.
    # Excluded: .io (socket.io), .org (many projects use org in name)
    DOCS_REPO_SUFFIXES = /
      (?:[-.](?:com|dev|net|site|website|pages|book))
      \z
    /ix

    # Repo names ending with "-docs" or "-documentation" → strip to get product slug.
    DOCS_REPO_SUFFIX_STRIP = /[-.](?:docs?|documentation)\z/i

    # Programming language names that are too generic ONLY when the owner is a
    # "bindings/SDK" org — NOT when the owner IS the language project itself.
    # e.g. clerk/javascript → clerk, but rust-lang/rust → rust (not rust-lang)
    GENERIC_LANG_NAMES = %w[
      javascript typescript python ruby go rust java kotlin swift elixir
      php csharp scala clojure haskell erlang lua perl r julia
    ].to_set.freeze
    GENERIC_HOST_LABELS = (GENERIC_SOURCE_NAMES + %w[www dev developer developers help support]).uniq.freeze
    LOCALE_PATH_SEGMENT = /\A[a-z]{2}(?:-[a-z]{2})?\z/i
    TITLE_SEPARATORS = /\s+[–—:-]\s+/
    GENERIC_TITLE_SUFFIX = /
      \s*
      (?:docs?|documentation|developer\s+docs?|guide|guides|manual|reference|
         api(?:\s+reference)?|site)
      \s*
    \z
    /ix

    module_function

    def from_git(owner:, repo_name:, source_url:)
      owner_slug = slugify(owner, fallback: "library")
      repo_slug = slugify(repo_name, fallback: owner_slug)
      product_slug = derive_git_product_slug(owner_slug, repo_slug, repo_name)

      {
        slug: product_slug,
        namespace: owner_slug,
        name: repo_slug,
        display_name: humanize_slug(product_slug),
        aliases: alias_set(
          product_slug,
          repo_slug,
          "#{owner_slug}/#{repo_slug}"
        )
      }
    end

    def from_llms(uri:, title:)
      product_slug = product_slug_from_uri(uri)
      cleaned_title = clean_title(title)

      {
        slug: product_slug,
        namespace: product_slug,
        name: product_slug,
        display_name: cleaned_title.presence || humanize_slug(product_slug),
        aliases: alias_set(product_slug, uri.host)
      }
    end

    def from_website(uri:, title: nil)
      product_slug = product_slug_from_uri(uri)
      cleaned_title = clean_title(title)

      {
        slug: product_slug,
        namespace: product_slug,
        name: product_slug,
        display_name: website_display_name(cleaned_title, product_slug),
        aliases: alias_set(product_slug, uri.host)
      }
    end

    def from_openapi(uri:, title:)
      host_slug = product_slug_from_uri(uri)
      cleaned_title = clean_title(title)
      title_slug = slugify(cleaned_title)
      product_slug = generic_title_slug?(title_slug) ? host_slug : (title_slug.presence || host_slug)

      {
        slug: product_slug,
        namespace: product_slug,
        name: product_slug,
        display_name: generic_title_slug?(title_slug) ? humanize_slug(product_slug) : (cleaned_title.presence || humanize_slug(product_slug)),
        aliases: alias_set(product_slug, host_slug, uri.host)
      }
    end

    def product_slug_from_uri(uri)
      host = uri.host.to_s.downcase.delete_prefix("www.")
      parts = host.split(".")
      first = slugify(parts.first)
      return first if first.present? && !generic_host_label?(first)

      if first.present? && generic_host_label?(first)
        if parts.length >= 3
          second = slugify(parts[1])
          return second if second.present?
        end

        path_slug = first_path_slug(uri)
        return path_slug if path_slug.present?
      end

      first.presence || first_path_slug(uri) || "library"
    end

    def clean_title(title)
      raw = title.to_s.gsub(/<[^>]+>/, " ").squish
      return if raw.blank?

      trimmed = raw.split(TITLE_SEPARATORS, 2).first.to_s.strip
      cleaned = trimmed.sub(GENERIC_TITLE_SUFFIX, "").strip
      cleaned.presence || trimmed.presence
    end

    def humanize_slug(slug)
      slug.to_s.split("-").map do |part|
        part.match?(/\A[a-z0-9]+\z/) ? part.capitalize : part
      end.join(" ")
    end

    def slugify(value, fallback: nil)
      slug = value.to_s.tr("_", "-").parameterize(separator: "-")
      slug.presence || fallback
    end

    # Derives the product slug for a git repo. Handles:
    # 1. Generic repo names (docs, core, cli) → use owner
    # 2. Docs website repos (nestjs/docs.nestjs.com, tailwindlabs/tailwindcss.com) → strip domain suffix
    # 3. Docs repos (drizzle-team/drizzle-orm-docs) → strip -docs suffix
    # 4. Generic language names (clerk/javascript) → use owner
    # 5. Normal repos → use repo name as-is
    def derive_git_product_slug(owner_slug, repo_slug, raw_repo_name)
      return owner_slug if generic_source_name?(repo_slug)

      # Generic language name (javascript, python, etc.) → use owner,
      # BUT only when the owner is clearly NOT the language project itself.
      # e.g. clerk/javascript → clerk, but rust-lang/rust → rust
      if GENERIC_LANG_NAMES.include?(repo_slug) && !owner_is_language_project?(owner_slug, repo_slug)
        return owner_slug
      end

      # Docs website repo: "docs.nestjs.com" → "nestjs", "tailwindcss.com" → "tailwindcss"
      if raw_repo_name.match?(DOCS_REPO_SUFFIXES)
        extracted = extract_product_from_docs_repo(raw_repo_name, owner_slug)
        return extracted if extracted.present?
      end

      # Docs repo: "drizzle-orm-docs" → "drizzle-orm"
      # Only strip when owner ≠ repo (terraform-docs/terraform-docs should stay as-is)
      if repo_slug.match?(DOCS_REPO_SUFFIX_STRIP) && owner_slug != repo_slug
        stripped = slugify(repo_slug.sub(DOCS_REPO_SUFFIX_STRIP, ""))
        return stripped if stripped.present? && !generic_source_name?(stripped)
      end

      repo_slug
    end

    # Check if the owner org is the language project itself.
    # e.g. rust-lang owns rust, golang owns go, swiftlang owns swift
    def owner_is_language_project?(owner_slug, repo_slug)
      # Owner contains the repo name (rust-lang contains rust, golang contains go)
      owner_slug.include?(repo_slug) ||
        # Or owner is a well-known language org pattern
        owner_slug.end_with?("-lang") ||
        owner_slug.end_with?("lang")
    end

    # Extract the product name from a docs website repo name.
    # "docs.nestjs.com" → "nestjs", "expressjs.com" → "expressjs",
    # "react.dev" → "react", "kamal-site" → "kamal"
    def extract_product_from_docs_repo(raw_repo_name, owner_slug)
      # Strip known suffixes: .com, .dev, .io, -site, -website, -pages, -book
      cleaned = raw_repo_name.sub(DOCS_REPO_SUFFIXES, "")
      # If it had dots (like docs.nestjs.com), split and find the product part
      parts = cleaned.split(".")
      # Filter out generic parts like "docs", "www"
      meaningful = parts.map { |p| slugify(p) }.reject { |p| generic_source_name?(p) || p.blank? }

      candidate = meaningful.last # innermost meaningful part (e.g. "nestjs" from "docs.nestjs")
      return candidate if candidate.present?

      # Fallback: use owner if nothing meaningful found
      owner_slug
    end

    def generic_source_name?(value)
      GENERIC_SOURCE_NAMES.include?(value.to_s.downcase)
    end

    def generic_title_slug?(value)
      parts = value.to_s.split("-").reject(&:blank?)
      parts.present? && parts.all? { |part| generic_source_name?(part) }
    end

    def generic_host_label?(value)
      GENERIC_HOST_LABELS.include?(value.to_s.downcase)
    end

    def first_path_slug(uri)
      uri.path.to_s.split("/").map { |part| slugify(part) }.find do |part|
        part.present? && !generic_source_name?(part) && !part.match?(LOCALE_PATH_SEGMENT)
      end
    end

    def website_display_name(cleaned_title, product_slug)
      return humanize_slug(product_slug) if cleaned_title.blank?

      title_slug = slugify(cleaned_title)
      return cleaned_title if title_slug == product_slug

      humanize_slug(product_slug)
    end

    def alias_set(*values)
      raw = values.flatten.filter_map do |value|
        candidate = value.to_s.strip.downcase.delete_prefix("www.")
        candidate.presence
      end

      condensed = raw.map { |value| value.gsub(/[^a-z0-9]/, "") }.reject(&:blank?)
      (raw + condensed).uniq
    end
  end
end
