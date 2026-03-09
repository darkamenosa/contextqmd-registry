# frozen_string_literal: true

class CrawlRequest < ApplicationRecord
  belongs_to :identity
  belongs_to :library, optional: true

  SOURCE_TYPES = %w[github gitlab website openapi llms_txt].freeze
  STATUSES = %w[pending processing completed failed cancelled].freeze

  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
  validates :source_type, presence: true, inclusion: { in: SOURCE_TYPES }
  validates :status, presence: true, inclusion: { in: STATUSES }

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

    def enqueue_processing
      ProcessCrawlRequestJob.perform_later(self)
    end
end
