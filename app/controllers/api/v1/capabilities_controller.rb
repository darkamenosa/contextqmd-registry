# frozen_string_literal: true

module Api
  module V1
    class CapabilitiesController < BaseController
      skip_before_action :authenticate_api_token!

      FEATURES = {
        bundle_download: true,
        signed_manifests: false,
        signed_fetch_recipes: false,
        origin_fetch_recipes: true,
        hosted_content: true,
        cursor_pagination: true,
        private_sources: false,
        delta_sync: false
      }.freeze

      SOURCE_TYPES = DocsFetcher::FETCHERS.keys.freeze

      def show
        render_data({
          name: "ContextQMD Registry",
          version: "1.1",
          features: FEATURES,
          source_types: SOURCE_TYPES
        })
      end
    end
  end
end
