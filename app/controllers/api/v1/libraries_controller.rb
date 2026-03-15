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
          search_results(params[:query])
        else
          paginated_catalog
        end

        render_data(
          libraries[:records].map { |lib| library_summary_json(lib) },
          cursor: libraries[:next_cursor]
        )
      end

      def show
        render_data(library_detail_json(@library))
      end

      private

        def search_libraries(query)
          normalized = query.to_s.strip
          by_alias = Library.where("aliases @> ?", [ normalized ].to_json).order(:slug)
          return by_alias if by_alias.exists?

          Library.search_by_query(normalized)
        end

        def search_results(query)
          per_page = resolve_per_page(nil)

          {
            records: search_libraries(query).includes(:versions, :source_policy).limit(per_page).to_a,
            next_cursor: nil
          }
        end

        def paginated_catalog
          paginate(Library.all.includes(:versions, :source_policy))
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
