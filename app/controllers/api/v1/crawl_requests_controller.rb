# frozen_string_literal: true

module Api
  module V1
    class CrawlRequestsController < BaseController
      MAX_BULK_URLS = 500

      # Write endpoints get a tighter per-identity rate limit on top of the global IP limit.
      rate_limit to: 20, within: 1.minute,
        by: -> { Current.identity&.id || request.remote_ip },
        only: [ :create, :bulk ]

      # POST /api/v1/crawl
      #
      # Params:
      #   url - URL to crawl (required). source_type is auto-detected.
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

      # POST /api/v1/crawl/bulk
      #
      # Params:
      #   urls - Array of URLs to crawl (required, max 500).
      def bulk
        urls = params.expect(urls: [])
        if urls.size > MAX_BULK_URLS
          return render_error(
            code: "too_many_urls",
            message: "Maximum #{MAX_BULK_URLS} URLs per request. Got #{urls.size}.",
            status: :unprocessable_entity
          )
        end

        creator = resolve_creator
        results = urls.map do |url|
          if url.blank?
            { url: url, status: "skipped", error: "blank URL" }
          else
            cr = CrawlRequest.new(url: url.to_s.strip, creator: creator)
            if cr.save
              { url: cr.url, id: cr.id, status: "queued" }
            else
              { url: url, status: "failed", error: cr.errors.full_messages.join(", ") }
            end
          end
        end

        queued = results.count { |r| r[:status] == "queued" }
        failed = results.count { |r| r[:status] == "failed" }
        skipped = results.count { |r| r[:status] == "skipped" }

        render_data(results, meta: { queued: queued, failed: failed, skipped: skipped, total: urls.size },
                             status: :accepted)
      end

      private

        # API tokens are identity-scoped (not tenant-scoped). The crawl pipeline is global,
        # so we pick the identity's first active user for attribution. Creator is optional.
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

        def render_data(data, cursor: nil, meta: {}, status: :ok)
          render json: { data: data, meta: meta.merge(cursor: cursor) }, status: status
        end
    end
  end
end
