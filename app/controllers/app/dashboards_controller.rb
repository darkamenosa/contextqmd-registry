# frozen_string_literal: true

module App
  class DashboardsController < BaseController
    def show
      render inertia: "app/dashboard/show", props: {
        stats: {
          library_count: Library.count,
          version_count: Version.count,
          page_count: Page.count,
          crawl_pending: CrawlRequest.pending.count
        },
        recent_crawls: Current.identity.crawl_requests.includes(:library).recent.limit(5).map { |cr| crawl_props(cr) },
        recent_libraries: Library.order(created_at: :desc).limit(5).map { |lib| library_props(lib) }
      }
    end

    private

      def crawl_props(cr)
        {
          id: cr.id,
          url: cr.url,
          source_type: cr.source_type,
          status: cr.status,
          library_name: cr.library&.display_name,
          library_slug: cr.library ? "#{cr.library.namespace}/#{cr.library.name}" : nil,
          created_at: cr.created_at.iso8601
        }
      end

      def library_props(lib)
        {
          namespace: lib.namespace,
          name: lib.name,
          display_name: lib.display_name,
          default_version: lib.default_version,
          created_at: lib.created_at.iso8601
        }
      end
  end
end
