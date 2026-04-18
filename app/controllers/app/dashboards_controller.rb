# frozen_string_literal: true

module App
  class DashboardsController < BaseController
    PAYLOAD_CACHE_TTL = 10.minutes

    def show
      state = dashboard_cache_state
      merge_vary_header!("X-Inertia")

      if flash.to_hash.present?
        response.headers["Cache-Control"] = "no-store"
      else
        request.session_options[:skip] = true if request.get? || request.head?

        fresh_when(
          etag: state[:etag],
          last_modified: state[:last_modified],
          public: false,
          template: false
        )
        return if performed?
      end

      render inertia: "app/dashboard/show", props: dashboard_payload(state)
    end

    private

      def my_crawl_requests
        @my_crawl_requests ||= Current.user.crawl_requests
      end

      def my_libraries
        @my_libraries ||= Library.where(id: my_crawl_requests.select(:library_id))
      end

      def dashboard_cache_state
        library_count,
          version_count,
          page_count,
          libraries_updated_at = my_libraries.pick(
            Arel.sql("COUNT(*)"),
            Arel.sql("COALESCE(SUM(libraries.versions_count), 0)"),
            Arel.sql("COALESCE(SUM(libraries.total_pages_count), 0)"),
            Arel.sql("MAX(libraries.updated_at)")
          )

        crawl_pending, crawls_updated_at = my_crawl_requests.pick(
          Arel.sql("COUNT(*) FILTER (WHERE status = 'pending')"),
          Arel.sql("MAX(updated_at)")
        )

        last_modified = [
          Current.account.updated_at,
          Current.identity.updated_at,
          Current.user.updated_at,
          crawls_updated_at,
          libraries_updated_at
        ].compact.max

        {
          stats: {
            library_count: library_count,
            version_count: version_count,
            page_count: page_count,
            crawl_pending: crawl_pending
          },
          etag: [
            "app-dashboard",
            Current.account.cache_key_with_version,
            Current.identity.cache_key_with_version,
            Current.user.cache_key_with_version,
            library_count,
            version_count,
            page_count,
            crawl_pending,
            last_modified&.to_fs(:usec)
          ],
          last_modified: last_modified
        }
      end

      def dashboard_payload(state)
        Rails.cache.fetch(
          [ "app-dashboard-payload", *state[:etag] ],
          expires_in: PAYLOAD_CACHE_TTL,
          race_condition_ttl: 10.seconds
        ) do
          recent_crawls = my_crawl_requests.includes(:library).recent.limit(5)
          recent_libraries = my_libraries.order(created_at: :desc).limit(5)

          {
            stats: state[:stats],
            recent_crawls: recent_crawls.map { |cr| crawl_props(cr) },
            recent_libraries: recent_libraries.map { |lib| library_props(lib) }
          }
        end
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
