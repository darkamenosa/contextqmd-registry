# frozen_string_literal: true

module App
  class CrawlRequestsController < BaseController
    def new
      render inertia: "app/crawl-requests/new"
    end

    def create
      crawl_request = Current.identity.crawl_requests.new(crawl_request_params)

      if crawl_request.save
        redirect_to crawl_requests_path, notice: "URL submitted for crawling!"
      else
        redirect_back fallback_location: new_app_crawl_request_path,
          alert: crawl_request.errors.full_messages.join(", ")
      end
    end

    private

      def crawl_request_params
        params.expect(crawl_request: [ :url ])
      end
  end
end
