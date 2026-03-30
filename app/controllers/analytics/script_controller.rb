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
      site = ::Analytics::Site.active.find_by(public_id: params[:website_id].to_s)
      if site.blank?
        head :not_found
        return
      end

      embed_context = resolved_embed_context_for(site)
      if embed_context.blank?
        head :forbidden
        return
      end

      Analytics::TrackerCorsHeaders.apply!(response.headers)
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
        module_src = "#{request.base_url}#{helpers.vite_asset_path('analytics.ts')}"
        bootstrap_path = helpers.analytics_tracker_bootstrap_path

        <<~JS
          (async () => {
            const currentScript = document.currentScript;
            if (typeof window.analytics !== "function") {
              window.__analyticsQueue = Array.isArray(window.__analyticsQueue) ? window.__analyticsQueue : [];
              window.analytics = (name, props) => {
                window.__analyticsQueue.push([name, props]);
              };
            }
            const existing =
              window.analyticsConfig && typeof window.analyticsConfig === "object"
                ? window.analyticsConfig
                : {};

            const next = { ...existing };
            next.transport = { ...(existing.transport || {}) };
            next.site = { ...(existing.site || {}) };
            next.tracking = { ...(existing.tracking || {}) };
            next.filters = { ...(existing.filters || {}) };

            const websiteId = currentScript?.getAttribute("data-website-id");
            const domainHint = currentScript?.getAttribute("data-domain");
            const eventsEndpoint = currentScript?.getAttribute("data-api");
            const includeAttr = currentScript?.getAttribute("data-include");
            const excludeAttr = currentScript?.getAttribute("data-exclude");

            if (websiteId) {
              next.site.websiteId = websiteId;
              next.websiteId = websiteId;
            }

            if (domainHint) {
              next.site.domainHint = domainHint;
              next.domainHint = domainHint;
            }

            if (eventsEndpoint) {
              next.transport.eventsEndpoint = eventsEndpoint;
              next.eventsEndpoint = eventsEndpoint;
            }

            if (includeAttr) {
              const includePaths = includeAttr
                .split(",")
                .map((entry) => entry.trim())
                .filter(Boolean);
              next.filters.includePaths = includePaths;
              next.includePaths = includePaths;
            }

            if (excludeAttr) {
              const extraPaths = excludeAttr
                .split(",")
                .map((entry) => entry.trim())
                .filter(Boolean);
              const basePaths = Array.isArray(next.filters.excludePaths)
                ? next.filters.excludePaths
                : Array.isArray(next.excludePaths)
                  ? next.excludePaths
                  : [];
              const excludePaths = Array.from(new Set([...basePaths, ...extraPaths]));
              next.filters.excludePaths = excludePaths;
              next.excludePaths = excludePaths;
            }

            if (websiteId && !next.site.token && !next.siteToken) {
              try {
                const bootstrapUrl = new URL(#{bootstrap_path.to_json}, currentScript?.src || window.location.href);
                bootstrapUrl.searchParams.set("website_id", websiteId);
                if (domainHint) bootstrapUrl.searchParams.set("domain", domainHint);

                const response = await fetch(bootstrapUrl.toString(), {
                  credentials: "omit",
                  mode: "cors",
                });

                if (response.ok) {
                  const bootstrap = await response.json();
                  if (bootstrap && typeof bootstrap === "object") {
                    Object.assign(next, bootstrap);
                    next.transport = {
                      ...(existing.transport || {}),
                      ...(next.transport || {}),
                      ...(bootstrap.transport || {}),
                    };
                    next.site = {
                      ...(existing.site || {}),
                      ...(next.site || {}),
                      ...(bootstrap.site || {}),
                    };
                    next.tracking = {
                      ...(existing.tracking || {}),
                      ...(next.tracking || {}),
                      ...(bootstrap.tracking || {}),
                    };
                    next.filters = {
                      ...(existing.filters || {}),
                      ...(next.filters || {}),
                      ...(bootstrap.filters || {}),
                    };
                  }
                }
              } catch (error) {
                console.warn("[analytics] failed to load tracker bootstrap", error);
              }
            }

            window.analyticsConfig = next;

            if (window.__analyticsModuleRequested) return;
            window.__analyticsModuleRequested = true;

            const moduleScript = document.createElement("script");
            moduleScript.type = "module";
            moduleScript.src = #{module_src.to_json};
            moduleScript.crossOrigin = "anonymous";
            (document.head || document.documentElement).appendChild(moduleScript);
          })();
        JS
      end

      def resolved_embed_context_for(site)
        source_uri = embed_source_uri
        return if source_uri.blank? || source_uri.host.blank?

        normalized_host = ::Analytics::SiteBoundary.normalize_host(source_uri.host)
        normalized_path = ::Analytics::SiteBoundary.normalize_path_prefix(source_uri.path)
        boundary = ::Analytics::SiteBoundary.resolve(host: normalized_host, path: normalized_path)

        if boundary.present?
          return if boundary.site != site

          return {
            host: normalized_host,
            path: normalized_path,
            boundary: boundary
          }
        end

        return unless same_site_host?(normalized_host, site.canonical_hostname)

        {
          host: normalized_host,
          path: normalized_path,
          boundary: nil
        }
      end

      def embed_source_uri
        candidates = [
          request.headers["Origin"],
          request.referer
        ].compact_blank

        candidates.each do |value|
          uri = URI.parse(value)
          return uri if uri.host.present?
        rescue URI::InvalidURIError
          next
        end

        nil
      end

      def same_site_host?(left, right)
        return false if left.to_s.strip.empty? || right.to_s.strip.empty?

        left.to_s.downcase.sub(/^www\./, "") == right.to_s.downcase.sub(/^www\./, "")
      end
  end
end
