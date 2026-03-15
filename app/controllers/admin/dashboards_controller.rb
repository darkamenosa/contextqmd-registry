# frozen_string_literal: true

module Admin
  class DashboardsController < BaseController
    def show
      pagy, recent_crawls = pagy(
        CrawlRequest.includes(:identity, :library).recent,
        limit: 10
      )

      render inertia: "admin/dashboard/show", props: {
        stats: {
          library_count: Library.count,
          version_count: Version.count,
          page_count: Page.count,
          identity_count: Identity.count,
          crawl_pending: CrawlRequest.pending.count,
          crawl_processing: CrawlRequest.processing.count,
          crawl_completed: CrawlRequest.completed.count,
          crawl_failed: CrawlRequest.failed.count
        },
        recent_crawls: recent_crawls.map { |cr| crawl_props(cr) },
        pagination: pagination_props(pagy)
      }
    end

    private

      def crawl_props(cr)
        {
          id: cr.id,
          url: cr.url,
          source_type: cr.source_type,
          status: cr.status,
          error_message: cr.error_message,
          submitted_by: cr.identity.email,
          library_name: cr.library&.display_name,
          library_slug: cr.library&.slug,
          created_at: cr.created_at.iso8601
        }
      end
  end
end
