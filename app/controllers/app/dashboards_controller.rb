# frozen_string_literal: true

module App
  class DashboardsController < BaseController
    def show
      recent_crawls = my_crawl_requests.includes(:library).recent.limit(5)
      recent_libraries = my_libraries.order(created_at: :desc).limit(5)

      render inertia: "app/dashboard/show", props: {
        stats: {
          library_count: my_libraries.count,
          version_count: my_versions.count,
          page_count: my_pages.count,
          crawl_pending: my_crawl_requests.pending.count
        },
        recent_crawls: recent_crawls.map { |cr| crawl_props(cr) },
        recent_libraries: recent_libraries.map { |lib| library_props(lib) }
      }
    end

    private

      def my_crawl_requests
        Current.user.crawl_requests
      end

      def my_libraries
        Library.where(id: my_crawl_requests.select(:library_id))
      end

      def my_versions
        Version.where(library_id: my_libraries.select(:id))
      end

      def my_pages
        Page.where(version_id: my_versions.select(:id))
      end

      def crawl_props(cr)
        {
          id: cr.id,
          url: cr.url,
          source_type: cr.source_type,
          status: cr.status,
          library_name: cr.library&.display_name,
          library_slug: cr.library&.slug,
          created_at: cr.created_at.iso8601
        }
      end

      def library_props(lib)
        {
          slug: lib.slug,
          display_name: lib.display_name,
          default_version: lib.default_version,
          created_at: lib.created_at.iso8601
        }
      end
  end
end
