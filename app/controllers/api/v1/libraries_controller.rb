# frozen_string_literal: true

module Api
  module V1
    class LibrariesController < BaseController
      skip_before_action :authenticate_api_token!
      include Concerns::CursorPaginatable

      def index
        libraries = if params[:query].present?
          search_libraries(params[:query])
        else
          Library.all
        end

        result = paginate(libraries)

        render_data(
          result[:records].map { |lib| library_json(lib) },
          cursor: result[:next_cursor]
        )
      end

      def show
        library = Library.find_by!(namespace: params[:namespace], name: params[:name])
        render_data(library_json(library))
      rescue ActiveRecord::RecordNotFound
        render_error(code: "not_found", message: "Library not found", status: :not_found)
      end

      private

        def search_libraries(query)
          # Try alias match first (jsonb containment)
          by_alias = Library.where("aliases @> ?", [ query ].to_json)
          return by_alias if by_alias.exists?

          # Fall back to pg_search
          Library.search_by_query(query)
        end

        def library_json(library)
          data = {
            namespace: library.namespace,
            name: library.name,
            display_name: library.display_name,
            aliases: library.aliases,
            homepage_url: library.homepage_url,
            default_version: library.default_version,
            version_count: library.versions.count
          }

          # Add stats for detail view (single library)
          if action_name == "show"
            default = library.versions.find_by(version: library.default_version) ||
                      library.versions.ordered.first
            if default
              data[:stats] = {
                page_count: default.pages.count,
                total_bytes: default.pages.sum(:bytes),
                last_generated_at: default.generated_at&.iso8601
              }
            end
          end

          data
        end
    end
  end
end
