# frozen_string_literal: true

module Api
  module V1
    class CrawlBatchesController < BaseController
      MAX_URLS = 500

      rate_limit to: 20, within: 1.minute,
        by: -> { Current.identity&.id || request.remote_ip },
        only: :create

      def create
        urls = params.expect(urls: [])

        if urls.size > MAX_URLS
          render_error(
            code: "too_many_urls",
            message: "Maximum #{MAX_URLS} URLs per request. Got #{urls.size}.",
            status: :unprocessable_entity
          )
        else
          results = batch_results(urls)
          render_data(results, meta: batch_meta(results, total: urls.size), status: :accepted)
        end
      end

      private

        def batch_meta(results, total:)
          queued = results.count { |result| result[:status] == "queued" }
          failed = results.count { |result| result[:status] == "failed" }
          skipped = results.count { |result| result[:status] == "skipped" }

          {
            queued: queued,
            failed: failed,
            skipped: skipped,
            total: total
          }
        end

        def preferred_creator
          Current.identity&.users&.find_by(role: :owner) || Current.identity&.users&.first
        end

        def batch_results(urls)
          @batch_results ||= begin
            creator = preferred_creator

            urls.map do |url|
              if url.blank?
                { url: url, status: "skipped", error: "blank URL" }
              else
                crawl_request = CrawlRequest.new(url: url.to_s.strip, creator: creator)

                if crawl_request.save
                  { url: crawl_request.url, id: crawl_request.id, status: "queued" }
                else
                  { url: url, status: "failed", error: crawl_request.errors.full_messages.join(", ") }
                end
              end
            end
          end
        end
    end
  end
end
