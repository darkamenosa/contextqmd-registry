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

      scope = apply_tab_filter(base).includes(:identity, :library)

      pagy, crawl_requests = pagy(:offset,
        scope.order(sort_column => sort_direction),
        limit: 25
      )

      render inertia: "admin/crawl-requests/index", props: {
        crawl_requests: crawl_requests.map { |cr| crawl_row_props(cr) },
        pagination: pagination_props(pagy),
        counts: {
          all: CrawlRequest.count,
          pending: CrawlRequest.pending.count,
          processing: CrawlRequest.processing.count,
          completed: CrawlRequest.completed.count,
          failed: CrawlRequest.failed.count,
          cancelled: CrawlRequest.cancelled.count
        },
        filters: {
          query: params[:query] || "",
          tab: params[:tab] || "all",
          sort: params[:sort] || "created_at",
          direction: params[:direction] || "desc"
        }
      }
    end

    def show
      cr = CrawlRequest.includes(:identity, :library, :library_source).find(params[:id])

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
          identity_email: cr.identity.email,
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
          identity_email: cr.identity.email,
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
