# frozen_string_literal: true

module Admin
  module CrawlRequests
    class CancellationsController < Admin::BaseController
      def create
        cr = CrawlRequest.find(params[:crawl_request_id])
        cr.mark_cancelled
        redirect_to admin_crawl_request_path(cr), notice: "Crawl request cancelled."
      end
    end
  end
end
