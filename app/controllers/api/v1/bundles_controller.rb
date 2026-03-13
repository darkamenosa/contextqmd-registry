# frozen_string_literal: true

module Api
  module V1
    class BundlesController < BaseController
      skip_before_action :authenticate_api_token!
      include Concerns::LibraryVersionLookup

      before_action :find_library_and_version!

      def show
        bundle = @version.bundles.find_by!(profile: safe_profile_param)

        if bundle.visibility_private?
          render_error(code: "not_found", message: "Bundle not found", status: :not_found)
        elsif bundle.ready? && bundle.download_url.present?
          redirect_to bundle.download_url, allow_other_host: true
        elsif bundle.ready? && bundle.available_locally?
          bundle_path = safe_bundle_file_path(bundle)

          if params[:sha256].present? && params[:sha256] == bundle.sha256
            expires_in 1.year, public: true, immutable: true
          else
            expires_in 5.minutes, public: true
          end
          response.headers["X-Bundle-SHA256"] = bundle.sha256
          send_file(
            bundle_path,
            filename: bundle.filename,
            type: DocsBundle::MIME_TYPE,
            disposition: "attachment"
          )
        elsif bundle.ready? && bundle.package.attached?
          if params[:sha256].present? && params[:sha256] == bundle.sha256
            expires_in 1.year, public: true, immutable: true
          else
            expires_in 5.minutes, public: true
          end
          response.headers["X-Bundle-SHA256"] = bundle.sha256
          send_data(
            bundle.package.download,
            filename: bundle.filename,
            type: DocsBundle::MIME_TYPE,
            disposition: "attachment"
          )
        elsif bundle.pending? || bundle.processing?
          render_error(code: "not_ready", message: "Bundle is not ready", status: :conflict)
        elsif bundle.failed?
          render_error(
            code: "bundle_failed",
            message: bundle.error_message.presence || "Bundle build failed",
            status: :service_unavailable
          )
        else
          render_error(code: "not_found", message: "Bundle file not found", status: :not_found)
        end
      rescue ActiveRecord::RecordNotFound
        render_error(code: "not_found", message: "Bundle not found", status: :not_found)
      end

      private
        def safe_profile_param
          profile = params[:profile].to_s
          return profile if profile.match?(Bundle::PATH_SAFE_PROFILE)

          raise ActiveRecord::RecordNotFound
        end

        def safe_bundle_file_path(bundle)
          path = bundle.file_path.expand_path
          root = DocsBundle.storage_root.expand_path
          path_string = path.to_s
          root_prefix = "#{root}/"

          if path_string == root.to_s || path_string.start_with?(root_prefix)
            path_string
          else
            raise ActiveRecord::RecordNotFound
          end
        rescue ArgumentError
          raise ActiveRecord::RecordNotFound
        end
    end
  end
end
