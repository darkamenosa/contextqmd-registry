# frozen_string_literal: true

module App
  class DashboardsController < BaseController
    def show
      recent_crawls = account_crawl_requests.includes(:library).recent.limit(5)
      recent_libraries = account_libraries.order(created_at: :desc).limit(5)

      render inertia: "app/dashboard/show", props: {
        stats: {
          library_count: account_libraries.count,
          version_count: account_versions.count,
          page_count: account_pages.count,
          crawl_pending: account_crawl_requests.pending.count
        },
        recent_crawls: recent_crawls.map { |cr| crawl_props(cr) },
        recent_libraries: recent_libraries.map { |lib| library_props(lib) }
      }
    end

    private

      def account_libraries
        Library.where(account: Current.account)
      end

      def account_versions
        Version.joins(:library).where(libraries: { account_id: Current.account.id })
      end

      def account_pages
        Page.joins(version: :library).where(libraries: { account_id: Current.account.id })
      end

      def account_crawl_requests
        Current.identity.crawl_requests.joins(:library).where(libraries: { account_id: Current.account.id })
      end

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
