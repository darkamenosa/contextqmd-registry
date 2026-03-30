# frozen_string_literal: true

class Analytics::TrackerBootstrap
  VERSION = 1
  DEFAULT_EXCLUDE_PATHS = [ "/admin", "/.well-known", "/ahoy", "/cable" ].freeze
  DEFAULT_EXCLUDE_ASSETS = [
    ".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp", ".ico", ".woff", ".woff2",
    ".ttf", ".eot", ".otf", ".pdf", ".zip", ".tar", ".gz", ".mp4", ".webm",
    ".mp3", ".wav", ".css", ".js", ".map", ".json"
  ].freeze

  class << self
    def build(request:, initial_pageview_tracked:, initial_page_key:)
      site_resolution = Analytics::TrackingSiteResolver.resolve(
        host: request.host,
        path: request.path,
        url: request.original_url
      )

      site_token = if site_resolution&.site.present?
        Analytics::TrackerSiteToken.generate(
          site: site_resolution.site,
          boundary: site_resolution.boundary,
          host: request.host,
          path: request.path,
          mode: "first_party"
        )
      end

      payload = {
        version: VERSION,
        transport: {
          eventsEndpoint: "/ahoy/events"
        },
        site: {
          token: site_token,
          domainHint: site_resolution&.site&.canonical_hostname.presence || request.host
        },
        tracking: {
          hashBasedRouting: false,
          initialPageviewTracked: initial_pageview_tracked == true,
          initialPageKey: initial_page_key
        },
        filters: {
          includePaths: [],
          excludePaths: DEFAULT_EXCLUDE_PATHS,
          excludeAssets: DEFAULT_EXCLUDE_ASSETS
        },
        debug: false,
        # Legacy flat fields kept during migration.
        eventsEndpoint: "/ahoy/events",
        useCookies: Analytics::Configuration.use_cookies?,
        visitDurationMinutes: Analytics::Configuration.visit_duration_minutes,
        useBeaconForEvents: Analytics::Configuration.use_beacon_for_events?,
        trackVisits: false,
        initialPageviewTracked: initial_pageview_tracked == true,
        initialPageKey: initial_page_key,
        siteToken: site_token,
        domainHint: site_resolution&.site&.canonical_hostname.presence || request.host
      }

      payload
    end
  end
end
