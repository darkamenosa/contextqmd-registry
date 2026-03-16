# frozen_string_literal: true

module DocsFetcher
  module LibraryIdentity
    GENERIC_SOURCE_NAMES = %w[
      api book doc docs documentation guide guides handbook manual manuals
      reference references site website wiki
    ].freeze
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
      product_slug = generic_source_name?(repo_slug) ? owner_slug : repo_slug

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
