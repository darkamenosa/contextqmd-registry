# frozen_string_literal: true

module Admin
  module CrawlRequests
    class RetriesController < Admin::BaseController
      def create
        original = CrawlRequest.find(params[:crawl_request_id])
        new_cr = CrawlRequest.create!(
          url: original.url,
          identity: original.identity,
          status: "pending",
          requested_bundle_visibility: original.requested_bundle_visibility,
          metadata: (original.metadata || {}).except("progress_current", "progress_total")
        )
        redirect_to admin_crawl_request_path(new_cr), notice: "Retry submitted."
      end
    end
  end
end
