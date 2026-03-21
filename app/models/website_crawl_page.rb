# frozen_string_literal: true

class WebsiteCrawlPage < ApplicationRecord
  belongs_to :website_crawl
  belongs_to :website_crawl_url

  validates :page_uid, :path, :title, :url, :content, presence: true
end
