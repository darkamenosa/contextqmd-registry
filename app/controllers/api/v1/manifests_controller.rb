# frozen_string_literal: true

module Api
  module V1
    class ManifestsController < BaseController
      include Concerns::LibraryVersionLookup

      before_action :find_library_and_version!

      def show
        render_data(manifest_json)
      end

      private

        def manifest_json
          {
            library: library_json,
            version: version_json,
            doc_count: @version.pages.count,
            source: source_json,
            page_index_url: page_index_url,
            profiles: @version.bundles.ordered.map { |b| b.profile },
            source_policy: source_policy_json,
            provenance: provenance_json
          }
        end

        def library_json
          {
            namespace: @library.namespace,
            name: @library.name,
            display_name: @library.display_name
          }
        end

        def version_json
          {
            version: @version.version,
            channel: @version.channel,
            generated_at: @version.generated_at&.iso8601,
            manifest_checksum: @version.manifest_checksum
          }
        end

        def source_json
          recipe = @version.fetch_recipe
          return nil unless recipe

          {
            source_type: recipe.source_type,
            url: recipe.url,
            normalizer_version: recipe.normalizer_version,
            splitter_version: recipe.splitter_version
          }
        end

        def page_index_url
          "/api/v1/libraries/#{@library.namespace}/#{@library.name}/versions/#{@version.version}/page-index"
        end

        def source_policy_json
          policy = @library.source_policy
          return nil unless policy

          {
            license_name: policy.license_name,
            license_status: policy.license_status,
            license_url: policy.license_url,
            mirror_allowed: policy.mirror_allowed,
            origin_fetch_allowed: policy.origin_fetch_allowed,
            attribution_required: policy.attribution_required
          }
        end

        def provenance_json
          {
            generated_at: @version.generated_at&.iso8601,
            source_url: @version.source_url
          }
        end
    end
  end
end
