# frozen_string_literal: true

module Api
  module V1
    class CrawlRequestsController < BaseController
      # POST /api/v1/crawl
      #
      # Params:
      #   url - URL to crawl (required). source_type is auto-detected.
      def create
        crawl_request = Current.identity.crawl_requests.new(crawl_request_params)

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

        def crawl_request_params
          { url: params.expect(:url) }
        end

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
