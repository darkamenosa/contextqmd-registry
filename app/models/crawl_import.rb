# frozen_string_literal: true

class CrawlImport
  include CrawlRequest::Importable

  delegate :library,
    :library_source,
    :metadata,
    :requested_bundle_visibility,
    :source_type,
    :url,
    to: :crawl_request

  def self.transaction(...)
    CrawlRequest.transaction(...)
  end

  def initialize(crawl_request)
    @crawl_request = crawl_request
  end

  def import!(result)
    import_result(result)
  end

  private

    attr_reader :crawl_request

    def update_progress(...)
      crawl_request.update_progress(...)
    end
end
