# frozen_string_literal: true

module Admin
  module Libraries
    class PagesController < Admin::BaseController
      def index
        version = Version.includes(:library).find(params[:version_id])
        scope = version.pages

        scope = scope.search_content(params[:query]) if params[:query].present?
        scope = scope.ordered unless params[:query].present?

        pagy, pages = pagy(scope, limit: 50)

        render inertia: "admin/versions/pages/index", props: {
          library: {
            id: version.library.id,
            display_name: version.library.display_name,
            namespace: version.library.namespace,
            name: version.library.name
          },
          version: {
            id: version.id,
            version: version.version,
            channel: version.channel
          },
          pages: pages.map { |p| page_props(p) },
          pagination: pagination_props(pagy),
          query: params[:query] || ""
        }
      end

      private

        def page_props(page)
          {
            id: page.id,
            page_uid: page.page_uid,
            path: page.path,
            title: page.title,
            bytes: page.description&.bytesize || 0,
            created_at: page.created_at.iso8601
          }
        end
    end
  end
end
