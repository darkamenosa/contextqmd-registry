# frozen_string_literal: true

class ProcessWebsiteCrawlJob < ApplicationJob
  include ActiveJob::Continuable

  queue_as :crawl_website

  discard_on ActiveJob::DeserializationError

  retry_on DocsFetcher::TransientFetchError, attempts: 3, wait: :polynomially_longer do |job, error|
    website_crawl = job.arguments.first
    website_crawl&.mark_pending_for_retry!
    website_crawl&.fail!(error.message)
  end

  def perform(website_crawl)
    @website_crawl = website_crawl
    return if @website_crawl.terminal?

    step :prepare do
      @prepare_result = @website_crawl.prepare!
    end
    return if @prepare_result == false

    step :fetch, start: 0 do |step|
      @website_crawl.fetch_pending!(step)
    end

    step :publish do
      @website_crawl.publish!
    end

    step :cleanup do
      @website_crawl.cleanup!
    end
  rescue DocsFetcher::TransientFetchError
    @website_crawl&.mark_pending_for_retry!
    @website_crawl&.crawl_request&.update_progress("Waiting to retry")
    raise
  rescue StandardError => error
    @website_crawl&.fail!(error.message)
    raise
  end
end
