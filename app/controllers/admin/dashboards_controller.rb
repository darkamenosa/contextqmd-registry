# frozen_string_literal: true

module Admin
  class DashboardsController < BaseController
    include PrivateInertiaPageCaching

    def show
      state = dashboard_cache_state
      return unless stale_private_inertia_page?(
        etag: state[:etag],
        last_modified: state[:last_modified]
      )

      pagy, recent_crawls = pagy(:offset,
        CrawlRequest.includes(:creator, :library).recent,
        limit: 10
      )

      render inertia: "admin/dashboard/show", props: {
        stats: state[:stats],
        recent_crawls: recent_crawls.map { |cr| crawl_props(cr) },
        pagination: pagination_props(pagy)
      }
    end

    private

      def dashboard_cache_state
        library_count,
          version_count,
          page_count,
          libraries_updated_at = Library.pick(
            Arel.sql("COUNT(*)"),
            Arel.sql("COALESCE(SUM(libraries.versions_count), 0)"),
            Arel.sql("COALESCE(SUM(libraries.total_pages_count), 0)"),
            Arel.sql("MAX(libraries.updated_at)")
          )

        crawl_count,
          crawl_pending,
          crawl_processing,
          crawl_completed,
          crawl_failed,
          crawls_updated_at = CrawlRequest.pick(
            Arel.sql("COUNT(*)"),
            Arel.sql("COUNT(*) FILTER (WHERE status = 'pending')"),
            Arel.sql("COUNT(*) FILTER (WHERE status = 'processing')"),
            Arel.sql("COUNT(*) FILTER (WHERE status = 'completed')"),
            Arel.sql("COUNT(*) FILTER (WHERE status = 'failed')"),
            Arel.sql("MAX(updated_at)")
          )

        identity_count = Identity.count
        default_membership = current_identity_default_membership
        default_account = default_membership&.account
        memberships_updated_at = Current.identity.users.maximum(:updated_at)
        last_modified = [
          Current.identity.updated_at,
          memberships_updated_at,
          default_membership&.updated_at,
          default_account&.updated_at,
          libraries_updated_at,
          crawls_updated_at
        ].compact.max

        {
          stats: {
            library_count: library_count,
            version_count: version_count,
            page_count: page_count,
            identity_count: identity_count,
            crawl_pending: crawl_pending,
            crawl_processing: crawl_processing,
            crawl_completed: crawl_completed,
            crawl_failed: crawl_failed
          },
          etag: [
            "admin-dashboard",
            params[:page].presence || "1",
            Current.identity.cache_key_with_version,
            default_membership&.cache_key_with_version,
            default_account&.cache_key_with_version,
            library_count,
            version_count,
            page_count,
            identity_count,
            crawl_count,
            crawl_pending,
            crawl_processing,
            crawl_completed,
            crawl_failed,
            last_modified&.to_fs(:usec)
          ],
          last_modified: last_modified
        }
      end

      def crawl_props(cr)
        {
          id: cr.id,
          url: cr.url,
          source_type: cr.source_type,
          status: cr.status,
          error_message: cr.error_message,
          submitted_by: cr.creator&.name || "System",
          library_name: cr.library&.display_name,
          library_slug: cr.library&.slug,
          created_at: cr.created_at.iso8601
        }
      end
  end
end
