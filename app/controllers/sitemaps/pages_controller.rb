# frozen_string_literal: true

module Sitemaps
  # GET /sitemap_pages_1.xml?from=1&to=100000
  #
  # Only includes default-version pages for libraries with content.
  # Uses default_version as the stable canonical target for SEO
  # (intentionally differs from best_version UI fallback logic).
  class PagesController < BaseController
    def index
      return head(:not_found) unless params[:from].present? && params[:to].present?

      @host = default_host

      scope = default_version_pages
                .where("pages.id >= ?", params[:from].to_i)
                .where("pages.id <= ?", params[:to].to_i)

      latest_update = scope.maximum("pages.updated_at") || Time.current

      if stale?(last_modified: latest_update, public: true)
        @pages = scope
        expires_in 1.hour, public: true
        render formats: :xml
      end
    end

    private

      def default_version_pages
        default_version_ids = Version.joins(:library)
                                     .merge(Library.indexable)
                                     .where("versions.version = libraries.default_version")
                                     .select(:id)

        Page.where(version_id: default_version_ids)
            .joins(version: :library)
            .select(
              "pages.id",
              "pages.page_uid",
              "pages.updated_at",
              "libraries.slug AS library_slug",
              "versions.version AS version_number"
            )
            .order("pages.id")
      end
  end
end
