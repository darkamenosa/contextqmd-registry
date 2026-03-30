# frozen_string_literal: true

module Analytics
  class ScriptController < ActionController::Base
    layout false
    skip_forgery_protection

    def show
      response.headers["Content-Type"] = "application/javascript; charset=utf-8"
      expires_now if Rails.env.development?

      render plain: loader_source
    end

    def bootstrap
      Analytics::TrackerCorsHeaders.apply!(response.headers)

      site = ::Analytics::Site.active.find_by(public_id: bootstrap_params[:website_id].to_s)
      if site.blank?
        head :not_found
        return
      end

      embed_context = resolved_embed_context_for(site)
      if embed_context.blank?
        head :forbidden
        return
      end

      render json: ::Analytics::TrackerBootstrap.build_external(
        site: site,
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

      def resolved_embed_context_for(site)
        source_uri = embed_source_uri
        return if source_uri.blank? || source_uri.host.blank?

        normalized_host = ::Analytics::SiteBoundary.normalize_host(source_uri.host)
        normalized_path = ::Analytics::SiteBoundary.normalize_path_prefix(source_uri.path)
        resolution = ::Analytics::TrackedSiteScope.resolve(
          host: normalized_host,
          url: source_uri.to_s,
          path: normalized_path,
          website_id: site.public_id
        )
        return if resolution.blank? || resolution.invalid_claim?

        {
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
