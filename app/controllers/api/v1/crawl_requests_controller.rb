# frozen_string_literal: true

module Api
  module V1
    class CrawlRequestsController < BaseController
      # POST /api/v1/crawl
      # Requires API token authentication.
      #
      # Params:
      #   url         - URL to crawl (required)
      #   source_type - optional, auto-detected from URL if omitted
      #
      # Returns the created crawl request with its status.
      def create
        crawl_request = Current.identity.crawl_requests.new(
          url: params[:url],
          source_type: params[:source_type]
        )

        if crawl_request.save
          render_data(crawl_request_json(crawl_request), meta: { status: "queued" })
        else
          render_error(
            code: "validation_error",
            message: crawl_request.errors.full_messages.join(", "),
            status: :unprocessable_entity
          )
        end
      end

      private

        def crawl_request_json(cr)
          {
            id: cr.id,
            url: cr.url,
            source_type: cr.source_type,
            status: cr.status,
            created_at: cr.created_at.iso8601
          }
        end
    end
  end
end
