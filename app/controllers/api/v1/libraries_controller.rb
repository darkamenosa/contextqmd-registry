# frozen_string_literal: true

module Api
  module V1
    class LibrariesController < BaseController
      skip_before_action :authenticate_api_token!
      include Concerns::LibraryVersionLookup
      include Concerns::CursorPaginatable

      before_action :find_library!, only: :show

      def index
        libraries = if params[:query].present?
          search_libraries(params[:query])
        else
          Library.all
        end

        result = paginate(libraries.includes(:versions))

        render_data(
          result[:records].map { |lib| library_summary_json(lib) },
          cursor: result[:next_cursor]
        )
      end

      def show
        render_data(library_detail_json(@library))
      end

      private

        def search_libraries(query)
          by_alias = Library.where("aliases @> ?", [ query ].to_json)
          return by_alias if by_alias.exists?

          Library.search_by_query(query)
        end

        def library_summary_json(library)
          serialize_library_summary(library).merge(version_count: library.versions.size)
        end

        def library_detail_json(library)
          data = library_summary_json(library)

          default = library.versions.find_by(version: library.default_version) ||
                    library.versions.ordered.first
          if default
            data[:stats] = {
              page_count: default.pages.count,
              total_bytes: default.pages.sum(:bytes),
              last_generated_at: default.generated_at&.iso8601
            }
          end

          data
        end
    end
  end
end
