# frozen_string_literal: true

module Admin
  class CrawlRequestsController < BaseController
    def index
      base = if params[:query].present?
        CrawlRequest.where(
          "url ILIKE :q OR error_message ILIKE :q OR status_message ILIKE :q",
          q: "%#{params[:query]}%"
        )
      else
        CrawlRequest.all
      end
      counts = {
        all: CrawlRequest.count,
        pending: CrawlRequest.pending.count,
        processing: CrawlRequest.processing.count,
        completed: CrawlRequest.completed.count,
        failed: CrawlRequest.failed.count,
        cancelled: CrawlRequest.cancelled.count
      }
      filtered_count = apply_tab_filter(base).count
      last_modified = [
        CrawlRequest.maximum(:updated_at),
        User.maximum(:updated_at),
        Library.maximum(:updated_at)
      ].compact.max

      merge_vary_header!("X-Inertia")

      if flash.to_hash.present?
        response.headers["Cache-Control"] = "no-store"
      else
        request.session_options[:skip] = true if request.get? || request.head?

        fresh_when(
          etag: [
            "admin-crawl-requests-index",
            params[:query].to_s,
            params[:tab] || "all",
            params[:sort] || "created_at",
            params[:direction] || "desc",
            params[:page].presence || "1",
            Current.identity.cache_key_with_version,
            filtered_count,
            counts[:all],
            counts[:pending],
            counts[:processing],
            counts[:completed],
            counts[:failed],
            counts[:cancelled],
            last_modified&.to_fs(:usec)
          ],
          last_modified: last_modified,
          public: false,
          template: false
        )
        return if performed?
      end

      scope = apply_tab_filter(base).includes(:creator, :library)

      pagy, crawl_requests = pagy(:offset,
        scope.order(sort_column => sort_direction),
        limit: 25
      )

      render inertia: "admin/crawl-requests/index", props: {
        crawl_requests: crawl_requests.map { |cr| crawl_row_props(cr) },
        pagination: pagination_props(pagy),
        counts: counts,
        filters: {
          query: params[:query] || "",
          tab: params[:tab] || "all",
          sort: params[:sort] || "created_at",
          direction: params[:direction] || "desc"
        }
      }
    end

    def show
      cr = CrawlRequest.includes(:creator, :library, :library_source).find(params[:id])

      render inertia: "admin/crawl-requests/show", props: {
        crawl_request: crawl_detail_props(cr)
      }
    end

    def destroy
      cr = CrawlRequest.find(params[:id])
      cr.destroy!
      redirect_to admin_crawl_requests_path, notice: "Crawl request deleted."
    end

    private

      def sort_column
        %w[url status created_at updated_at started_at completed_at].include?(params[:sort]) ? params[:sort] : "created_at"
      end

      def sort_direction
        %w[asc desc].include?(params[:direction]) ? params[:direction] : "desc"
      end

      def apply_tab_filter(scope)
        case params[:tab]
        when "pending" then scope.pending
        when "processing" then scope.processing
        when "completed" then scope.completed
        when "failed" then scope.failed
        when "cancelled" then scope.cancelled
        else scope
        end
      end

      def crawl_row_props(cr)
        {
          id: cr.id,
          url: cr.url,
          source_type: cr.source_type,
          status: cr.status,
          status_message: cr.status_message,
          error_message: cr.error_message,
          requested_bundle_visibility: cr.requested_bundle_visibility,
          creator_name: cr.creator&.name || "System",
          library_id: cr.library_id,
          library_slug: cr.library&.slug,
          library_display_name: cr.library&.display_name,
          duration_seconds: cr.duration&.round,
          started_at: cr.started_at&.iso8601,
          completed_at: cr.completed_at&.iso8601,
          created_at: cr.created_at.iso8601,
          updated_at: cr.updated_at.iso8601
        }
      end

      def crawl_detail_props(cr)
        {
          id: cr.id,
          url: cr.url,
          source_type: cr.source_type,
          status: cr.status,
          status_message: cr.status_message,
          error_message: cr.error_message,
          requested_bundle_visibility: cr.requested_bundle_visibility,
          creator_name: cr.creator&.name || "System",
          library_id: cr.library_id,
          library_slug: cr.library&.slug,
          library_display_name: cr.library&.display_name,
          library_source_id: cr.library_source_id,
          library_source_url: cr.library_source&.url,
          metadata: cr.metadata,
          duration_seconds: cr.duration&.round,
          started_at: cr.started_at&.iso8601,
          completed_at: cr.completed_at&.iso8601,
          created_at: cr.created_at.iso8601,
          updated_at: cr.updated_at.iso8601
        }
      end
  end
end
