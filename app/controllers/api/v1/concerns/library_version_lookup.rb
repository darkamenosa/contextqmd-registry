# frozen_string_literal: true

module Api
  module V1
    module Concerns
      module LibraryVersionLookup
        extend ActiveSupport::Concern

        private

          def find_library!
            @library = Library.find_by!(namespace: params[:namespace], name: params[:name])
          rescue ActiveRecord::RecordNotFound
            render_error(code: "not_found", message: "Library not found", status: :not_found)
          end

          def find_library_and_version!
            @library = Library.find_by!(namespace: params[:namespace], name: params[:name])
            @version = @library.versions.find_by!(version: params[:version])
          rescue ActiveRecord::RecordNotFound
            render_error(code: "not_found", message: "Library or version not found", status: :not_found)
          end

          # Shared serializers — single source of truth for API JSON shapes.
          # Used by VersionsController, ManifestsController, ResolveController, LibrariesController.

          def serialize_library_summary(library)
            {
              namespace: library.namespace,
              name: library.name,
              display_name: library.display_name,
              aliases: library.aliases,
              homepage_url: library.homepage_url,
              default_version: library.default_version
            }
          end

          def serialize_version_summary(version)
            {
              version: version.version,
              channel: version.channel,
              generated_at: version.generated_at&.iso8601,
              manifest_checksum: version.manifest_checksum
            }
          end
      end
    end
  end
end
