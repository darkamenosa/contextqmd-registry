# frozen_string_literal: true

module Api
  module V1
    class ManifestsController < BaseController
      skip_before_action :authenticate_api_token!
      include Concerns::LibraryVersionLookup

      before_action :find_library_and_version!

      def show
        cache_key = [
          "manifest",
          @library.id,
          @version.id,
          @version.manifest_checksum,
          @version.fetch_recipe&.cache_key_with_version,
          @library.source_policy&.cache_key_with_version,
          bundle_cache_key
        ]
        data = Rails.cache.fetch(cache_key, expires_in: 1.hour) { manifest_json }
        render_data(data)
      end

      private

        def manifest_json
          recipe = @version.fetch_recipe

          {
            schema_version: "1.0",
            slug: @library.slug,
            display_name: @library.display_name,
            version: @version.version,
            channel: @version.channel,
            generated_at: @version.generated_at&.iso8601,
            doc_count: @version.pages.count,
            source: source_json(recipe),
            page_index: {
              url: "/api/v1/libraries/#{@library.slug}/versions/#{@version.version}/page-index",
              sha256: nil
            },
            profiles: profiles_json,
            source_policy: source_policy_json,
            provenance: provenance_json(recipe)
          }
        end

        def source_json(recipe)
          return nil unless recipe

          {
            type: recipe.source_type,
            url: recipe.url
          }
        end

        def profiles_json
          bundles = @version.bundles.ready.with_attached_package.ordered.select do |bundle|
            bundle.visibility_public? && bundle.deliverable?
          end
          return {} if bundles.empty?

          bundles.each_with_object({}) do |bundle, hash|
            hash[bundle.profile] = {
              bundle: {
                format: bundle.format,
                url: bundle_url(bundle),
                sha256: bundle.sha256
              }
            }
          end
        end

        def source_policy_json
          policy = @library.source_policy
          return nil unless policy

          {
            license_name: policy.license_name,
            license_status: policy.license_status,
            mirror_allowed: policy.mirror_allowed,
            origin_fetch_allowed: policy.origin_fetch_allowed,
            attribution_required: policy.attribution_required
          }
        end

        def provenance_json(recipe)
          {
            normalizer_version: recipe&.normalizer_version,
            splitter_version: recipe&.splitter_version,
            manifest_checksum: @version.manifest_checksum
          }
        end

        def bundle_cache_key
          bundle_state = @version.bundles.ordered.pluck(:profile, :status, :visibility, :format, :sha256, :updated_at)
          Digest::SHA256.hexdigest(bundle_state.to_json)
        end

        def bundle_url(bundle)
          return bundle.manifest_url if bundle.manifest_url.present?

          path = "/api/v1/libraries/#{@library.slug}/versions/#{@version.version}/bundles/#{bundle.profile}"
          return path if bundle.sha256.blank?

          "#{path}?sha256=#{ERB::Util.url_encode(bundle.sha256)}"
        end
    end
  end
end
