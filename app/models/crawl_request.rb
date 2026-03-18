# frozen_string_literal: true

require "zlib"

class CrawlRequest < ApplicationRecord
  include Importable

  SYSTEM_ACCOUNT_NAME = "ContextQMD System"
  SYSTEM_ACCOUNT_LOCK_KEY = Zlib.crc32(SYSTEM_ACCOUNT_NAME).freeze
  SYSTEM_IDENTITY_EMAIL = "crawler@contextqmd.local"
  SYSTEM_IDENTITY_LOCK_KEY = Zlib.crc32(SYSTEM_IDENTITY_EMAIL).freeze

  belongs_to :identity
  belongs_to :library, optional: true
  belongs_to :library_source, optional: true

  SOURCE_TYPES = %w[github gitlab bitbucket git website openapi llms_txt].freeze
  STATUSES = %w[pending processing completed failed cancelled].freeze
  BUNDLE_VISIBILITIES = %w[public private].freeze

  enum :status, STATUSES.index_by(&:itself), default: :pending

  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
  validates :source_type, presence: true, inclusion: { in: SOURCE_TYPES }
  validates :requested_bundle_visibility, presence: true, inclusion: { in: BUNDLE_VISIBILITIES }
  validate :url_not_private, if: -> { url.present? }

  normalizes :url, with: -> { it.to_s.strip }

  before_validation :detect_source_type, if: -> { url.present? }
  after_create_commit :enqueue_processing

  scope :recent, -> { order(created_at: :desc) }

  def self.system_identity
    with_system_identity_lock do
      Identity.find_or_create_by!(email: SYSTEM_IDENTITY_EMAIL) do |identity|
        password = SecureRandom.hex(24)
        identity.password = password
        identity.password_confirmation = password
      end
    end
  end

  def mark_cancelled
    raise "Cannot cancel from #{status}" if completed? || cancelled?
    update!(status: "cancelled", completed_at: Time.current, status_message: "Cancelled")
  end

  # Owns the full crawl lifecycle: fetch → import → complete/fail.
  # Called by ProcessCrawlRequestJob (thin job, rich model pattern).
  def process
    return unless pending? || processing?
    return if cancelled?

    mark_processing if pending?

    update_progress("Fetching documentation")
    result = DocsFetcher.for(source_type).fetch(self, on_progress: method(:update_progress))

    update_progress("Importing 0/#{result.pages.size} pages", current: 0, total: result.pages.size)
    self.class.transaction do
      library, source = import_result(result)
      mark_completed(library, source)
    end
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

    # --- Callbacks ---

    def detect_source_type
      return if preserve_library_source_source_type?

      self.source_type = DocsFetcher.detect_source_type(url)
    end

    def preserve_library_source_source_type?
      library_source.present? && source_type.present? && source_type == library_source.source_type
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

    def self.with_system_identity_lock
      return yield unless Identity.connection.adapter_name == "PostgreSQL"

      Identity.transaction do
        lock_sql = Identity.send(
          :sanitize_sql_array,
          [ "SELECT pg_advisory_xact_lock(?)", SYSTEM_IDENTITY_LOCK_KEY ]
        )
        Identity.connection.execute(lock_sql)
        yield
      end
    end
end
