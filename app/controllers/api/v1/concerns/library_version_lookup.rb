# frozen_string_literal: true

module Api
  module V1
    module Concerns
      module LibraryVersionLookup
        extend ActiveSupport::Concern

        private

          def find_library!
            @library = Library.includes(:source_policy, :versions).find_by!(slug: params[:slug])
          rescue ActiveRecord::RecordNotFound
            render_error(code: "not_found", message: "Library not found", status: :not_found)
          end

          def find_library_and_version!
            @library = Library.find_by!(slug: params[:slug])
            @version = resolve_url_version(@library, params[:version])
            raise ActiveRecord::RecordNotFound unless @version
          rescue ActiveRecord::RecordNotFound
            render_error(code: "not_found", message: "Library or version not found", status: :not_found)
          end

          def resolve_url_version(library, version_param)
            case version_param
            when "latest"
              library.versions.find_by(version: library.default_version) || library.versions.ordered.first
            when "stable"
              library.versions.stable.ordered.first
            else
              library.versions.find_by(version: version_param)
            end
          end

          # Shared serializers — single source of truth for API JSON shapes.
          # Used by VersionsController, ManifestsController, ResolveController, LibrariesController.

          def serialize_library_summary(library)
            {
              slug: library.slug,
              display_name: library.display_name,
              aliases: library.aliases,
              homepage_url: library.homepage_url,
              default_version: library.default_version,
              source_type: library.source_type,
              license_status: library.source_policy&.license_status
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
