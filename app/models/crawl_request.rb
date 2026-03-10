# frozen_string_literal: true

require "ipaddr"
require "resolv"

class CrawlRequest < ApplicationRecord
  belongs_to :identity
  belongs_to :library, optional: true

  SOURCE_TYPES = %w[github gitlab website openapi llms_txt].freeze
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

  def complete!(library)
    update!(status: "completed", library: library, error_message: nil)
  end

  def fail!(message)
    update!(status: "failed", error_message: message)
  end

  def start_processing!
    update!(status: "processing")
  end

  def processing?
    status == "processing"
  end

  def completed?
    status == "completed"
  end

  private

    def detect_source_type
      self.source_type = DocsFetcher.detect_source_type(url)
    end

    PRIVATE_RANGES = [
      IPAddr.new("127.0.0.0/8"),
      IPAddr.new("10.0.0.0/8"),
      IPAddr.new("172.16.0.0/12"),
      IPAddr.new("192.168.0.0/16"),
      IPAddr.new("169.254.0.0/16"),
      IPAddr.new("::1/128"),
      IPAddr.new("fc00::/7")
    ].freeze

    def url_not_private
      host = URI.parse(url).host
      return if host.blank?

      # Block localhost aliases
      if host.match?(/\A(localhost|0\.0\.0\.0|127\.\d+\.\d+\.\d+)\z/i)
        errors.add(:url, "must not point to a private address")
        return
      end

      # Resolve DNS and check IP ranges
      addrs = Resolv.getaddresses(host)
      if addrs.any? { |addr| PRIVATE_RANGES.any? { |range| range.include?(IPAddr.new(addr)) rescue false } }
        errors.add(:url, "must not point to a private address")
      end
    rescue URI::InvalidURIError
      errors.add(:url, "is not a valid URL")
    rescue Resolv::ResolvError
      # Can't resolve — allow (will fail at fetch time)
    end

    def enqueue_processing
      ProcessCrawlRequestJob.perform_later(self)
    end
end
