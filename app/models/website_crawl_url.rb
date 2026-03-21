# frozen_string_literal: true

class WebsiteCrawlUrl < ApplicationRecord
  STATUSES = %w[pending fetched skipped failed].freeze

  belongs_to :website_crawl
  has_one :website_crawl_page, dependent: :delete

  enum :status, STATUSES.index_by(&:itself), default: :pending

  validates :url, presence: true
  validates :normalized_url, presence: true
end
