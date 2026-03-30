# frozen_string_literal: true

module Analytics
  class ScriptController < ActionController::Base
    layout false
    skip_forgery_protection

    def show
      source = loader_source

      if Rails.env.development?
        expires_now
      else
        return unless stale?(etag: source, public: true)
      end

      render js: source
    end

    def bootstrap
      Analytics::TrackerCorsHeaders.apply!(response.headers)

      embed_context = resolved_bootstrap_scope
      if embed_context.blank?
        head :forbidden
        return
      end

      render json: ::Analytics::TrackerBootstrap.build_external(
        site: embed_context[:site],
        request: request,
        boundary: embed_context[:boundary],
        host: embed_context[:host],
        path: embed_context[:path]
      )
    end

    private
      def loader_source
        Analytics::TrackerLoader.build(
          module_src: tracker_module_src,
          bootstrap_path: helpers.analytics_tracker_bootstrap_path
        )
      end

      def tracker_module_src
        "#{request.base_url}#{helpers.vite_asset_path('analytics.ts')}"
      end

      def resolved_bootstrap_scope
        source_uri = embed_source_uri
        return if source_uri.blank? || source_uri.host.blank?

        normalized_host = ::Analytics::SiteBoundary.normalize_host(source_uri.host)
        normalized_path = ::Analytics::SiteBoundary.normalize_path_prefix(source_uri.path)
        resolution = ::Analytics::TrackedSiteScope.resolve(
          host: normalized_host,
          url: source_uri.to_s,
          path: normalized_path,
          website_id: bootstrap_params[:website_id].to_s
        )
        return if resolution.blank? || resolution.invalid_claim?

        {
          site: resolution.site,
          host: normalized_host,
          path: normalized_path,
          boundary: resolution.boundary
        }
      end

      def embed_source_uri
        candidates = [
          request.referer,
          request.headers["Origin"]
        ].compact_blank

        candidates.each do |value|
          uri = URI.parse(value)
          return uri if uri.host.present?
        rescue URI::InvalidURIError
          next
        end

        nil
      end

      def bootstrap_params
        params.permit(:website_id)
      end
  end
end
