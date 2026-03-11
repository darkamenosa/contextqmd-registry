# frozen_string_literal: true

require "zlib"

class CrawlRequest < ApplicationRecord
  SYSTEM_ACCOUNT_NAME = "ContextQMD System"
  SYSTEM_ACCOUNT_LOCK_KEY = Zlib.crc32(SYSTEM_ACCOUNT_NAME).freeze

  belongs_to :identity
  belongs_to :library, optional: true

  SOURCE_TYPES = %w[github gitlab bitbucket git website openapi llms_txt].freeze
  STATUSES = %w[pending processing completed failed cancelled].freeze

  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
  validates :source_type, presence: true, inclusion: { in: SOURCE_TYPES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validate :url_not_private, if: -> { url.present? }

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
    library = import_result(result)

    mark_completed(library)
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

  def mark_completed(library)
    raise "Cannot complete from #{status}" unless processing?
    update!(status: "completed", library: library, error_message: nil,
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
      library = find_or_create_library(result)
      version = find_or_create_version(library, result)
      sync_pages(version, result.pages, prune_stale: result.complete)
      record_fetch_recipe(version)
      update_manifest_checksum(version)

      if should_promote_default_version?(library, version)
        library.update!(default_version: version.version)
      end

      library
    end

    def find_or_create_library(result)
      system_account = ensure_system_account
      namespace_slug = library_slug(result.namespace, prefix: "ns")
      name_slug = library_slug(result.name, prefix: "lib")

      library = Library.find_by(namespace: namespace_slug, name: name_slug)

      unless library
        candidates = (result.aliases || []) + [ result.name, name_slug ]
        candidates.each do |candidate|
          library = Library.where("aliases @> ?", [ candidate ].to_json).first
          break if library
        end
      end

      library ||= find_or_create_record(
        Library,
        { namespace: namespace_slug, name: name_slug },
        account: system_account,
        display_name: result.display_name,
        homepage_url: result.homepage_url,
        aliases: result.aliases,
        source_type: source_type
      )

      merged_aliases = ((library.aliases || []) + (result.aliases || []) + [ result.name, name_slug ]).uniq
      library.update!(
        display_name: result.display_name.presence || library.display_name,
        aliases: merged_aliases,
        homepage_url: result.homepage_url.presence || library.homepage_url,
        source_type: source_type
      )

      library
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
      slug = value.to_s.parameterize(separator: "-")
      return slug if slug.present?

      "#{prefix}-#{Digest::SHA256.hexdigest(value.to_s)[0, 12]}"
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

    def record_fetch_recipe(version)
      recipe = version.fetch_recipe || version.build_fetch_recipe
      recipe.assign_attributes(
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
