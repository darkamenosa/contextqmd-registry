# frozen_string_literal: true

module Api
  module V1
    class PageIndexController < BaseController
      include Concerns::LibraryVersionLookup

      before_action :find_library_and_version!

      def index
        pages = @version.pages.ordered

        render_data(
          pages.map { |p| page_summary_json(p) },
          meta: { cursor: nil }
        )
      end

      def show
        page = @version.pages.find_by!(page_uid: params[:page_uid])

        render_data(page_detail_json(page))
      rescue ActiveRecord::RecordNotFound
        render_error(code: "not_found", message: "Page not found", status: :not_found)
      end

      private

        def page_summary_json(page)
          {
            page_uid: page.page_uid,
            path: page.path,
            title: page.title,
            url: page.url,
            checksum: page.checksum,
            bytes: page.bytes,
            headings: page.headings,
            updated_at: page.updated_at&.iso8601
          }
        end

        def page_detail_json(page)
          {
            page_uid: page.page_uid,
            path: page.path,
            title: page.title,
            url: page.url,
            content_md: page.description
          }
        end
    end
  end
end
