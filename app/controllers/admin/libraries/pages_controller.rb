# frozen_string_literal: true

module Admin
  module Libraries
    class PagesController < Admin::BaseController
      include Admin::VersionScoped

      before_action :set_page, only: %i[show edit update destroy]

      def index
        scope = @version.pages
        scope = scope.search_content(params[:query]) if params[:query].present?
        scope = scope.ordered unless params[:query].present?

        pagy, pages = pagy(:offset, scope, limit: 50)

        render inertia: "admin/versions/pages/index", props: {
          library: library_summary_props,
          version: version_summary_props,
          pages: pages.map { |p| page_row_props(p) },
          pagination: pagination_props(pagy),
          query: params[:query] || ""
        }
      end

      def show
        render inertia: "admin/pages/show", props: {
          page: page_show_props(@page),
          version: version_summary_props,
          library: library_summary_props
        }
      end

      def edit
        render inertia: "admin/pages/edit", props: {
          page: page_edit_props(@page),
          version: version_summary_props,
          library: { id: @library.id, display_name: @library.display_name }
        }
      end

      def update
        if @page.update(page_params)
          redirect_to edit_admin_library_version_page_path(@library, @version, @page), notice: "Page updated."
        else
          redirect_to edit_admin_library_version_page_path(@library, @version, @page),
            alert: @page.errors.full_messages.join(", ")
        end
      end

      def destroy
        @page.destroy!
        redirect_to admin_library_version_pages_path(@library, @version),
          notice: "Page deleted."
      end

      private

        def set_page
          @page = @version.pages.find(params[:id])
        end

        def page_params
          params.expect(page: [ :title, :description ])
        end

        def library_summary_props
          {
            id: @library.id,
            display_name: @library.display_name,
            namespace: @library.namespace,
            name: @library.name
          }
        end

        def version_summary_props
          {
            id: @version.id,
            version: @version.version,
            channel: @version.channel
          }
        end

        def page_row_props(page)
          {
            id: page.id,
            page_uid: page.page_uid,
            path: page.path,
            title: page.title,
            bytes: page.description&.bytesize || 0,
            created_at: page.created_at.iso8601
          }
        end

        def page_show_props(page)
          {
            id: page.id,
            page_uid: page.page_uid,
            path: page.path,
            title: page.title,
            url: page.url,
            content: page.description || "",
            bytes: page.description&.bytesize || 0,
            checksum: page.checksum,
            source_ref: page.source_ref,
            headings: page.headings || [],
            created_at: page.created_at.iso8601,
            updated_at: page.updated_at.iso8601
          }
        end

        def page_edit_props(page)
          {
            id: page.id,
            page_uid: page.page_uid,
            path: page.path,
            title: page.title,
            content: page.description || "",
            bytes: page.description&.bytesize || 0
          }
        end
    end
  end
end
