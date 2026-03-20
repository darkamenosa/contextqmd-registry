# frozen_string_literal: true

module Api
  module V1
    class CrawlRequestsController < BaseController
      rate_limit to: 20, within: 1.minute,
        by: -> { Current.identity&.id || request.remote_ip },
        only: :create

      def create
        crawl_request = CrawlRequest.new(url: params.expect(:url), creator: resolve_creator)

        if crawl_request.save
          render_data(crawl_request_json(crawl_request), meta: { status: "queued" }, status: :accepted)
        else
          render_error(
            code: "validation_error",
            message: crawl_request.errors.full_messages.join(", "),
            status: :unprocessable_entity
          )
        end
      end

      private

        def resolve_creator
          Current.identity&.users&.find_by(role: :owner) || Current.identity&.users&.first
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
