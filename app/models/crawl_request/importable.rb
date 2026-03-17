# frozen_string_literal: true

# Extracted import pipeline for CrawlRequest.
# Handles: library matching/creation, source linking, version management,
# page syncing, fetch recipe recording, manifest checksums, and bundle scheduling.
module CrawlRequest::Importable
  extend ActiveSupport::Concern

  private

    # --- Import pipeline (invocation order) ---

    def import_result(result)
      result = apply_canonical_metadata_overrides(result)
      existing_source = find_existing_library_source
      library = find_or_create_library(result, existing_source: existing_source)
      source = find_or_create_library_source(library, existing_source: existing_source)
      version = find_or_create_version(library, result)
      sync_pages(version, result.pages)
      version.reconcile_pages_count
      record_fetch_recipe(version, source)
      update_manifest_checksum(version)
      schedule_full_bundle(version)

      if should_promote_default_version?(library, version)
        library.update!(default_version: version.version)
      end

      [ library, source ]
    end

    def find_or_create_library(result, existing_source: nil)
      slug = library_slug(result.slug, prefix: "lib")
      namespace_slug = library_slug(result.namespace, prefix: "ns")
      name_slug = library_slug(result.name, prefix: "lib")
      existing_source_library = preferred_existing_source_library(
        existing_source,
        result,
        slug: slug,
        namespace_slug: namespace_slug,
        name_slug: name_slug
      )

      library = self.library || existing_source_library || find_matching_library_for_import(
        result,
        slug: slug,
        namespace_slug: namespace_slug,
        name_slug: name_slug
      )

      library ||= create_library_record(
        result,
        slug: slug,
        namespace_slug: namespace_slug,
        name_slug: name_slug
      )

      sync_library_metadata(library, result, slug: slug, namespace_slug: namespace_slug, name_slug: name_slug)

      library
    end

    def find_matching_library_for_import(result, slug:, namespace_slug:, name_slug:)
      if git_source_import?
        if prefer_canonical_git_match?(slug: slug, name_slug: name_slug)
          existing = find_existing_library(canonical_lookup_values(result, slug: slug, namespace_slug: namespace_slug, name_slug: name_slug))
          return existing if existing
        end

        return Library.find_by(namespace: namespace_slug, name: name_slug)
      end

      find_existing_library([
        slug,
        result.slug,
        result.namespace,
        namespace_slug,
        result.name,
        name_slug,
        *(result.aliases || [])
      ].reject { |v| generic_alias?(v) })
    end

    def preferred_existing_source_library(existing_source, result, slug:, namespace_slug:, name_slug:)
      return existing_source&.library unless existing_source.present?
      return existing_source.library unless prefer_canonical_git_match?(slug: slug, name_slug: name_slug)

      find_existing_library(canonical_lookup_values(result, slug: slug, namespace_slug: namespace_slug, name_slug: name_slug)) || existing_source.library
    end

    def create_library_record(result, slug:, namespace_slug:, name_slug:)
      unique_attrs = { namespace: namespace_slug, name: name_slug }
      create_attrs = {
        account: ensure_system_account,
        display_name: result.display_name,
        homepage_url: result.homepage_url,
        aliases: (result.aliases || []).reject { |v| generic_alias?(v) },
        source_type: source_type
      }

      loop do
        library = Library.find_by(unique_attrs)
        return library if library

        library = Library.create!(
          unique_attrs.merge(
            create_attrs.merge(
              slug: next_available_library_slug(slug, namespace_slug: namespace_slug, name_slug: name_slug)
            )
          )
        )
        return library
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
        library = Library.find_by(unique_attrs)
        return library if library
        raise unless slug_conflict?(e)
      end
    end

    def find_or_create_library_source(library, existing_source: nil)
      normalized_url = LibrarySource.normalize_url(url, source_type: source_type)
      source = library_source || existing_source || library.library_sources.find_or_initialize_by(url: normalized_url)
      source.library = library
      source.assign_attributes(
        url: normalized_url,
        source_type: source_type,
        active: true,
        primary: primary_library_source?(library, source)
      )
      source.crawl_rules = library.crawl_rules if source.crawl_rules.blank? && library.crawl_rules.present?
      source.last_crawled_at = Time.current
      source.save!
      source
    end

    def sync_library_metadata(library, result, slug:, namespace_slug:, name_slug:)
      merged_aliases = normalized_aliases(
        (library.aliases || []) +
        (result.aliases || []) +
        [ result.slug, slug, result.namespace, namespace_slug, result.name, name_slug ]
      ).reject { |v| generic_alias?(v) }

      attrs = {
        aliases: merged_aliases
      }
      attrs[:slug] = slug if should_update_library_slug?(library, slug)
      attrs[:source_type] = source_type if library.source_type.blank?

      unless library.metadata_locked?
        attrs[:display_name] = result.display_name.presence || library.display_name
      end

      attrs[:homepage_url] = if library.metadata_locked? && library.homepage_url.present?
        library.homepage_url
      else
        result.homepage_url.presence || library.homepage_url
      end

      library.update!(attrs)
    end

    def find_existing_library(values)
      normalized_aliases(values).each do |candidate|
        library = Library.find_by(slug: candidate)
        return library if library

        library = Library.where("aliases @> ?", [ candidate ].to_json).first
        return library if library
      end

      nil
    end

    def find_existing_library_source
      return library_source if library_source.present?

      LibrarySource.find_matching(url: url, source_type: source_type)
    end

    def primary_library_source?(library, source)
      !library.library_sources.where(primary: true).where.not(id: source.id).exists?
    end

    def next_available_library_slug(base_slug, namespace_slug:, name_slug:)
      base = library_slug(base_slug, prefix: "lib")
      namespace_name = [ namespace_slug, name_slug ].uniq.join("-")
      candidates = [ base ]
      candidates << namespace_name unless namespace_name == base
      candidates << "#{namespace_slug}-#{base}" unless namespace_slug == base

      candidates.each do |candidate|
        return candidate unless Library.exists?(slug: candidate)
      end

      suffix = 2
      loop do
        candidate = "#{namespace_name}-#{suffix}"
        return candidate unless Library.exists?(slug: candidate)

        suffix += 1
      end
    end

    def find_or_create_version(library, result)
      version_tag = result.version || "latest"
      version = find_or_create_record(
        library.versions,
        { version: version_tag },
        channel: Version.channel_for(result.version),
        generated_at: Time.current
      )
      version.channel = Version.channel_for(result.version)
      version.generated_at = Time.current
      version.save!
      version
    end

    def should_promote_default_version?(library, candidate_version)
      return true if library.default_version.blank?

      current_default = library.versions.find_by(version: library.default_version)
      return true unless current_default
      return false if current_default.version == candidate_version.version

      current_priority = default_version_priority(current_default.channel)
      candidate_priority = default_version_priority(candidate_version.channel)
      return candidate_priority > current_priority if candidate_priority != current_priority

      comparison = Version.compare(candidate_version.version, current_default.version)
      comparison && comparison.positive?
    end

    def apply_canonical_metadata_overrides(result)
      canonical_slug = canonical_slug_override
      canonical_display_name = canonical_display_name_override
      return result if canonical_slug.blank? && canonical_display_name.blank?

      CrawlResult.new(
        slug: canonical_slug.presence || result.slug,
        namespace: result.namespace,
        name: result.name,
        display_name: canonical_display_name.presence || result.display_name,
        homepage_url: result.homepage_url,
        aliases: normalized_aliases(Array(result.aliases) + [ canonical_slug ]),
        version: result.version,
        pages: result.pages,
        complete: result.complete
      )
    end

    def default_version_priority(channel)
      case channel
      when "stable"
        2
      when "latest"
        1
      else
        0
      end
    end

    def library_slug(value, prefix:)
      slug = value.to_s.tr("_", "-").parameterize(separator: "-")
      return slug if slug.present?

      "#{prefix}-#{Digest::SHA256.hexdigest(value.to_s)[0, 12]}"
    end

    def normalized_aliases(values)
      raw = values.map(&:to_s).map(&:strip).reject(&:blank?)
      compact = raw.map { |value| value.downcase.gsub(/[^a-z0-9]/, "") }.reject(&:blank?)
      (raw + compact).uniq
    end

    def canonical_lookup_values(result, slug:, namespace_slug:, name_slug:)
      [
        canonical_slug_override,
        slug,
        result.slug,
        result.namespace,
        namespace_slug,
        result.name,
        name_slug,
        *(result.aliases || [])
      ].reject { |value| generic_alias?(value) }
    end

    def prefer_canonical_git_match?(slug:, name_slug:)
      canonical_slug_override.present? || slug != name_slug
    end

    def should_update_library_slug?(library, slug)
      return false if slug.blank? || library.slug == slug
      return true if library.slug.blank?
      return false unless canonical_slug_override.present?
      return false if library.metadata_locked?

      !Library.where.not(id: library.id).exists?(slug: slug)
    end

    def generic_alias?(value)
      DocsFetcher::LibraryIdentity::GENERIC_SOURCE_NAMES.include?(value.to_s.downcase.strip)
    end

    def git_source_import?
      source_type.in?(%w[github gitlab bitbucket git])
    end

    def slug_conflict?(error)
      return true if error.is_a?(ActiveRecord::RecordNotUnique)
      return false unless error.is_a?(ActiveRecord::RecordInvalid)

      error.record&.errors&.attribute_names&.include?(:slug)
    end

    def canonical_slug_override
      metadata_string("canonical_slug")
    end

    def canonical_display_name_override
      metadata_string("canonical_display_name")
    end

    def metadata_string(key)
      value = metadata&.[](key) || metadata&.[](key.to_sym)
      value.to_s.strip.presence
    end

    def sync_pages(version, pages)
      # Clean slate: delete all existing pages before importing fresh content.
      version.pages.delete_all
      total = pages.size

      pages.each_with_index do |page_data, index|
        content = sanitize_content(page_data[:content].to_s)
        checksum = Digest::SHA256.hexdigest(content)

        version.pages.create!(
          page_uid: page_data[:page_uid],
          path: page_data[:path],
          title: page_data[:title],
          url: page_data[:url],
          description: content,
          bytes: content.bytesize,
          checksum: checksum,
          source_ref: source_type,
          headings: sanitize_headings(page_data[:headings] || [])
        )

        if (index + 1) % 10 == 0 || index + 1 == total
          update_progress("Importing #{index + 1}/#{total} pages", current: index + 1, total: total)
        end
      end
    end

    STRIP_TAGS = %w[SYSTEM system-reminder system_reminder IMPORTANT].freeze

    def sanitize_content(content)
      STRIP_TAGS.each do |tag|
        content = content.gsub(%r{</?#{Regexp.escape(tag)}[^>]*>}i, "")
      end
      content = content.gsub(/\s*\{\/\*.*?\*\/\}/, "")
      content.strip
    end

    def sanitize_headings(headings)
      headings.map { |h| h.gsub(/\s*\{\/\*.*?\*\/\}/, "").strip }.reject(&:blank?)
    end

    def record_fetch_recipe(version, source)
      recipe = version.fetch_recipe || version.build_fetch_recipe
      recipe.assign_attributes(
        library_source: source,
        source_type: source_type,
        url: url,
        normalizer_version: "1.0",
        splitter_version: "1.0"
      )
      recipe.save!
    end

    def update_manifest_checksum(version)
      page_checksums = version.pages.order(:page_uid).pluck(:checksum).compact
      return if page_checksums.empty?

      manifest_checksum = Digest::SHA256.hexdigest(page_checksums.join)
      version.update!(manifest_checksum: manifest_checksum)
    end

    def schedule_full_bundle(version)
      if version.pages.exists?
        version.bundles.find_or_initialize_by(profile: "full").tap do |bundle|
          bundle.visibility = requested_bundle_visibility
          bundle.build_later
        end
      end
    end

    def ensure_system_account
      with_system_account_lock do
        account = Account.find_or_create_by!(name: CrawlRequest::SYSTEM_ACCOUNT_NAME, personal: false)
        account.users.find_or_create_by!(role: :system) { |user| user.name = "System" }
        account
      end
    end

    def with_system_account_lock
      return yield unless Account.connection.adapter_name == "PostgreSQL"

      Account.transaction do
        lock_sql = Account.send(
          :sanitize_sql_array,
          [ "SELECT pg_advisory_xact_lock(?)", CrawlRequest::SYSTEM_ACCOUNT_LOCK_KEY ]
        )
        Account.connection.execute(lock_sql)
        yield
      end
    end

    def find_or_create_record(relation, unique_attrs, create_attrs = {})
      relation.find_by(unique_attrs) || relation.create!(unique_attrs.merge(create_attrs))
    rescue ActiveRecord::RecordNotUnique
      relation.find_by!(unique_attrs)
    end
end
