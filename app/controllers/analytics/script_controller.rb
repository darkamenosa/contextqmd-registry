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

    private
      def loader_source
        module_src = "#{request.base_url}#{helpers.vite_asset_path('analytics.ts')}"

        <<~JS
          (() => {
            const currentScript = document.currentScript;
            const existing =
              window.analyticsConfig && typeof window.analyticsConfig === "object"
                ? window.analyticsConfig
                : {};

            const next = { ...existing };
            next.transport = { ...(existing.transport || {}) };
            next.site = { ...(existing.site || {}) };
            next.tracking = { ...(existing.tracking || {}) };
            next.filters = { ...(existing.filters || {}) };

            const siteToken = currentScript?.getAttribute("data-site-token");
            const domainHint = currentScript?.getAttribute("data-domain");
            const eventsEndpoint = currentScript?.getAttribute("data-api");
            const includeAttr = currentScript?.getAttribute("data-include");
            const excludeAttr = currentScript?.getAttribute("data-exclude");

            if (siteToken) {
              next.site.token = siteToken;
              next.siteToken = siteToken;
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
  end
end
