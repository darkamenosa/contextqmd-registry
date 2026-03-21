# frozen_string_literal: true

class CrawlPipeline
  def self.for(crawl_request)
    case crawl_request.source_type
    when "website"
      Website.new(crawl_request)
    else
      Standard.new(crawl_request)
    end
  end

  class Standard
    def initialize(crawl_request)
      @crawl_request = crawl_request
    end

    def dispatch!
      StandardCrawl.new(crawl_request).process
    end

    private

      attr_reader :crawl_request
  end

  class Website
    def initialize(crawl_request)
      @crawl_request = crawl_request
    end

    def dispatch!
      return unless crawl_request.pending?

      WebsiteCrawl.start!(crawl_request)
    end

    private

      attr_reader :crawl_request
  end
end
