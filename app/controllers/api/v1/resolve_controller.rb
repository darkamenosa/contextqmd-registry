# frozen_string_literal: true

module Api
  module V1
    class ResolveController < BaseController
      def create
        query = params[:query]
        return render_error(code: "bad_request", message: "Query parameter is required", status: :bad_request) if query.blank?

        library = find_library(query)
        return render_error(code: "not_found", message: "No library found for '#{query}'", status: :not_found) unless library

        version = resolve_version(library, params[:version_hint])
        return render_error(code: "not_found", message: "No matching version found", status: :not_found) unless version

        render_data({
          library: serialize_library(library),
          version: serialize_version(version)
        })
      end

      private

        def find_library(query)
          # 1. Try namespace/name exact match
          if query.include?("/")
            namespace, name = query.split("/", 2)
            found = Library.find_by(namespace: namespace, name: name)
            return found if found
          end

          # 2. Try exact name match
          found = Library.find_by(name: query)
          return found if found

          # 3. Try alias match (jsonb containment)
          found = Library.where("aliases @> ?", [ query ].to_json)
          return found.first if found.exists?

          # 4. Fall back to pg_search
          results = Library.search_by_query(query)
          results.first
        end

        def resolve_version(library, version_hint)
          case version_hint
          when nil, "", "latest"
            resolve_latest(library)
          when "stable"
            library.versions.stable.ordered.first
          else
            library.versions.find_by(version: version_hint)
          end
        end

        def resolve_latest(library)
          if library.default_version.present?
            library.versions.find_by(version: library.default_version) || library.versions.ordered.first
          else
            library.versions.ordered.first
          end
        end

        def serialize_library(library)
          {
            namespace: library.namespace,
            name: library.name,
            display_name: library.display_name,
            aliases: library.aliases,
            homepage_url: library.homepage_url,
            default_version: library.default_version
          }
        end

        def serialize_version(version)
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
