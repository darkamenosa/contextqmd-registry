# frozen_string_literal: true

module Api
  module V1
    class BundlesController < BaseController
      include Concerns::LibraryVersionLookup

      before_action :find_library_and_version!

      def show
        bundle = @version.bundles.find_by!(profile: params[:profile])

        render_data(bundle_json(bundle))
      rescue ActiveRecord::RecordNotFound
        render_error(code: "not_found", message: "Bundle not found", status: :not_found)
      end

      private

        def bundle_json(bundle)
          {
            profile: bundle.profile,
            format: bundle.format,
            sha256: bundle.sha256,
            size_bytes: bundle.size_bytes,
            url: bundle.url
          }
        end
    end
  end
end
