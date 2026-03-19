# frozen_string_literal: true

module Admin
  module CrawlRequests
    class RetriesController < Admin::BaseController
      include Admin::CrawlRequestScoped

      def create
        new_cr = CrawlRequest.create!(
          url: @crawl_request.url,
          creator: @crawl_request.creator,
          status: "pending",
          requested_bundle_visibility: @crawl_request.requested_bundle_visibility,
          metadata: (@crawl_request.metadata || {}).except("progress_current", "progress_total")
        )
        redirect_to admin_crawl_request_path(new_cr), notice: "Retry submitted."
      end
    end
  end
end
