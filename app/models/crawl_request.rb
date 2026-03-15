# frozen_string_literal: true

require "zlib"

class CrawlRequest < ApplicationRecord
  SYSTEM_ACCOUNT_NAME = "ContextQMD System"
  SYSTEM_ACCOUNT_LOCK_KEY = Zlib.crc32(SYSTEM_ACCOUNT_NAME).freeze

  belongs_to :identity
  belongs_to :library, optional: true
  belongs_to :library_source, optional: true

  SOURCE_TYPES = %w[github gitlab bitbucket git website openapi llms_txt].freeze
  STATUSES = %w[pending processing completed failed cancelled].freeze
  BUNDLE_VISIBILITIES = %w[public private].freeze

  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
  validates :source_type, presence: true, inclusion: { in: SOURCE_TYPES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :requested_bundle_visibility, presence: true, inclusion: { in: BUNDLE_VISIBILITIES }
  validate :url_not_private, if: -> { url.present? }

  normalizes :url, with: -> { it.to_s.strip }

  before_validation :detect_source_type, if: -> { url.present? }
  after_create_commit :enqueue_processing

  scope :pending, -> { where(status: "pending") }
  scope :processing, -> { where(status: "processing") }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :recent, -> { order(created_at: :desc) }

  def pending?
    status == "pending"
  end

  def processing?
    status == "processing"
  end

  def completed?
    status == "completed"
  end

  # Owns the full crawl lifecycle: fetch → import → complete/fail.
  # Called by ProcessCrawlRequestJob (thin job, rich model pattern).
  def process
    return unless pending? || processing?

    mark_processing if pending?

    update_progress("Fetching documentation")
    result = DocsFetcher.for(source_type).fetch(self, on_progress: method(:update_progress))

    update_progress("Importing #{result.pages.size} pages")
    library, source = import_result(result)

    mark_completed(library, source)
  rescue DocsFetcher::TransientFetchError
    # Let job framework retry — don't mark as failed yet
    update_progress("Waiting to retry")
    raise
  rescue StandardError => e
    # Permanent failure — mark failed immediately
    mark_failed(e.message) unless completed?
    raise
  end

  def mark_processing
    raise "Cannot start processing from #{status}" unless pending?
    update!(status: "processing", started_at: Time.current, status_message: "Starting")
  end

  def mark_completed(library, source = nil)
    raise "Cannot complete from #{status}" unless processing?
    update!(status: "completed", library: library, library_source: source, error_message: nil,
            completed_at: Time.current, status_message: "Completed")
  end

  def mark_failed(message)
    raise "Cannot fail from #{status}" if completed?
    update!(status: "failed", error_message: message,
            completed_at: Time.current, status_message: "Failed")
  end

  def update_progress(message, current: nil, total: nil)
    attrs = { status_message: message, updated_at: Time.current }
    if current || total
      attrs[:metadata] = (metadata || {}).merge(
        "progress_current" => current,
        "progress_total" => total
      )
    end
    update_columns(attrs)
  end

  def duration
    if started_at && completed_at
      completed_at - started_at
    elsif started_at
      Time.current - started_at
    end
  end

  private

    # --- Import pipeline (invocation order) ---

    def import_result(result)
      existing_source = find_existing_library_source
      library = find_or_create_library(result, existing_source: existing_source)
      source = find_or_create_library_source(library, existing_source: existing_source)
      version = find_or_create_version(library, result)
      sync_pages(version, result.pages, prune_stale: result.complete)
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

      library = self.library || existing_source&.library || find_existing_library([
        slug,
        result.slug,
        result.namespace,
        namespace_slug,
        result.name,
        name_slug,
        *(result.aliases || [])
      ].reject { |v| generic_alias?(v) })

      library ||= find_or_create_record(
        Library,
        { namespace: namespace_slug, name: name_slug },
        account: ensure_system_account,
        slug: slug,
        display_name: result.display_name,
        homepage_url: result.homepage_url,
        aliases: (result.aliases || []).reject { |v| generic_alias?(v) },
        source_type: source_type
      )

      sync_library_metadata(library, result, slug: slug, namespace_slug: namespace_slug, name_slug: name_slug)

      library
    end

    def find_or_create_library_source(library, existing_source: nil)
      normalized_url = LibrarySource.normalize_url(url, source_type: source_type)
      source = library_source || existing_source || library.library_sources.find_or_initialize_by(url: normalized_url)
      source.assign_attributes(
        url: normalized_url,
        source_type: source_type,
        active: true,
        primary: library.library_sources.where(primary: true).none? || source.primary?
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
      attrs[:slug] = slug if library.slug.blank?
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

    def generic_alias?(value)
      DocsFetcher::LibraryIdentity::GENERIC_SOURCE_NAMES.include?(value.to_s.downcase.strip)
    end

    def sync_pages(version, pages, prune_stale: true)
      incoming_uids = Set.new
      total = pages.size

      pages.each_with_index do |page_data, index|
        content = sanitize_content(page_data[:content].to_s)
        checksum = Digest::SHA256.hexdigest(content)
        uid = page_data[:page_uid]
        incoming_uids << uid

        page = find_or_create_record(
          version.pages,
          { page_uid: uid },
          path: page_data[:path],
          title: page_data[:title],
          url: page_data[:url],
          description: content,
          bytes: content.bytesize,
          checksum: checksum,
          source_ref: source_type,
          headings: sanitize_headings(page_data[:headings] || [])
        )
        page.assign_attributes(
          path: page_data[:path],
          title: page_data[:title],
          url: page_data[:url],
          description: content,
          bytes: content.bytesize,
          checksum: checksum,
          source_ref: source_type,
          headings: sanitize_headings(page_data[:headings] || [])
        )
        page.save! if page.changed?

        # Debounce progress updates (every 10 pages or last page)
        if (index + 1) % 10 == 0 || index + 1 == total
          update_progress("Importing pages", current: index + 1, total: total)
        end
      end

      # Only prune stale pages on complete harvests. Partial/bounded crawls
      # (website, truncated llms.txt) merge without deleting previously good pages.
      if prune_stale && incoming_uids.any?
        version.pages.where.not(page_uid: incoming_uids.to_a).destroy_all
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

    # --- Callbacks ---

    def detect_source_type
      self.source_type = DocsFetcher.detect_source_type(url)
    end

    def url_not_private
      uri = URI.parse(url)
      unless SsrfGuard.safe_uri?(uri)
        errors.add(:url, "must not point to a private address")
      end
    rescue URI::InvalidURIError
      errors.add(:url, "is not a valid URL")
    end

    def enqueue_processing
      ProcessCrawlRequestJob.perform_later(self)
    end

    def ensure_system_account
      with_system_account_lock do
        account = Account.find_or_create_by!(name: SYSTEM_ACCOUNT_NAME, personal: false)
        account.users.find_or_create_by!(role: :system) { |user| user.name = "System" }
        account
      end
    end

    def with_system_account_lock
      return yield unless Account.connection.adapter_name == "PostgreSQL"

      Account.transaction do
        lock_sql = Account.send(
          :sanitize_sql_array,
          [ "SELECT pg_advisory_xact_lock(?)", SYSTEM_ACCOUNT_LOCK_KEY ]
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
