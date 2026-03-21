# frozen_string_literal: true

class StandardCrawl
  def initialize(crawl_request)
    @crawl_request = crawl_request
  end

  def process
    return unless crawl_request.begin_processing!

    result = nil

    crawl_request.update_progress("Fetching documentation")
    result = DocsFetcher.for(crawl_request.source_type).fetch(crawl_request, on_progress: crawl_request.method(:update_progress))

    crawl_request.reload
    return if crawl_request.cancelled?

    crawl_request.update_progress("Importing 0/#{result.pages.size} pages", current: 0, total: result.pages.size)
    CrawlRequest.transaction do
      library, source = CrawlImport.new(crawl_request).import!(result)
      crawl_request.mark_completed(library, source)
    end
  rescue DocsFetcher::TransientFetchError
    crawl_request.update_progress("Waiting to retry")
    raise
  rescue StandardError => error
    crawl_request.reload
    crawl_request.mark_failed(error.message) unless crawl_request.terminal?
    raise
  ensure
    result&.pages&.cleanup! if result&.pages&.respond_to?(:cleanup!)
  end

  private

    attr_reader :crawl_request
end
