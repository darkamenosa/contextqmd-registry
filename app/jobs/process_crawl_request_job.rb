# frozen_string_literal: true

class ProcessCrawlRequestJob < ApplicationJob
  discard_on ActiveJob::DeserializationError

  queue_as :default

  # Transient errors (DNS, timeout, 5xx, rate limits) get retried.
  # Initial attempt + 2 retries = 3 total attempts.
  retry_on DocsFetcher::TransientFetchError, attempts: 3, wait: :polynomially_longer do |job, error|
    crawl_request = job.arguments.first
    crawl_request&.mark_failed(error.message)
  end

  def perform(crawl_request)
    CrawlPipeline.for(crawl_request).dispatch!
  end
end
