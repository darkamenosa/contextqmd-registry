# frozen_string_literal: true

class Analytics::TrackerLoader
  SCRIPT_PATH = "/analytics/script.js".freeze

  class << self
    def script_path
      SCRIPT_PATH
    end

    def build(module_src:, bootstrap_path:)
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
          if (websiteId) {
            next.site.websiteId = websiteId;
          }

          if (websiteId && !next.site.token) {
            try {
              const bootstrapUrl = new URL(#{bootstrap_path.to_json}, currentScript?.src || window.location.href);
              const response = await fetch(bootstrapUrl.toString(), {
                method: "POST",
                headers: {
                  "Content-Type": "application/json",
                },
                body: JSON.stringify({ website_id: websiteId }),
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
  end
end
