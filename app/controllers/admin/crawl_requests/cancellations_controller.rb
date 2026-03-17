# frozen_string_literal: true

module Admin
  module CrawlRequests
    class CancellationsController < Admin::BaseController
      include Admin::CrawlRequestScoped

      def create
        @crawl_request.mark_cancelled
        redirect_to admin_crawl_request_path(@crawl_request), notice: "Crawl request cancelled."
      end
    end
  end
end
