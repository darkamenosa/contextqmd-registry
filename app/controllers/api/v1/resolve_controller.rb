# frozen_string_literal: true

module Api
  module V1
    class ResolveController < BaseController
      skip_before_action :authenticate_api_token!
      include Concerns::LibraryVersionLookup
      rate_limit to: 120, within: 1.minute, by: -> { request.remote_ip }, only: :create

      def create
        query = params.expect(:query)

        library = find_library(query)
        return render_error(code: "not_found", message: "No library found for '#{query}'", status: :not_found) unless library

        version = resolve_version(library, params[:version_hint])
        return render_error(code: "not_found", message: "No matching version found", status: :not_found) unless version

        render_data({
          library: serialize_library_summary(library),
          version: serialize_version_summary(version),
          manifest_url: "/api/v1/libraries/#{library.slug}/versions/#{version.version}/manifest"
        })
      end

      private

        def find_library(query)
          # 1. Try exact canonical slug match
          found = Library.find_by(slug: query)
          return found if found

          # 2. Try alias match (jsonb containment)
          found = Library.where("aliases @> ?", [ query ].to_json)
          return found.first if found.exists?

          # 3. Fall back to pg_search
          results = Library.search_by_query(query)
          results.first
        end

        def resolve_version(library, version_hint)
          case version_hint
          when nil, "", "latest"
            resolve_latest(library)
          when "stable", "canary", "snapshot"
            library.versions.where(channel: version_hint).ordered.first
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
    end
  end
end
