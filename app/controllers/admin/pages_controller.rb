# frozen_string_literal: true

module Admin
  class PagesController < BaseController
    before_action :set_page, only: [ :show, :edit, :update, :destroy ]

    def show
      render inertia: "admin/pages/show", props: {
        page: page_show_props(@page),
        version: {
          id: @page.version.id,
          version: @page.version.version
        },
        library: {
          id: @page.version.library.id,
          display_name: @page.version.library.display_name,
          namespace: @page.version.library.namespace,
          name: @page.version.library.name
        }
      }
    end

    def edit
      render inertia: "admin/pages/edit", props: {
        page: page_edit_props(@page),
        version: {
          id: @page.version.id,
          version: @page.version.version
        },
        library: {
          id: @page.version.library.id,
          display_name: @page.version.library.display_name
        }
      }
    end

    def update
      if @page.update(page_params)
        redirect_to edit_admin_page_path(@page), notice: "Page updated."
      else
        redirect_to edit_admin_page_path(@page),
          alert: @page.errors.full_messages.join(", ")
      end
    end

    def destroy
      library = @page.version.library
      version = @page.version
      @page.destroy!
      redirect_to admin_version_pages_path(version),
        notice: "Page deleted."
    end

    private

      def set_page
        @page = Page.includes(version: :library).find(params[:id])
      end

      def page_params
        params.expect(page: [ :title, :description ])
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
