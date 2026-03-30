# frozen_string_literal: true

class Analytics::TrackerBootstrap
  VERSION = 1
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
      tracking_rules = Analytics::TrackingRules.effective(site: site_resolution&.site)

      site_token = if site_resolution&.site.present?
        Analytics::TrackerSiteToken.generate(
          site: site_resolution.site,
          boundary: site_resolution.boundary,
          host: request.host,
          path: request.path,
          mode: "first_party"
        )
      end

      {
        version: VERSION,
        transport: {
          eventsEndpoint: "/analytics/events"
        },
        site: {
          websiteId: site_resolution&.site&.public_id,
          token: site_token,
          domainHint: site_resolution&.site&.canonical_hostname.presence || request.host
        },
        tracking: {
          hashBasedRouting: false,
          initialPageviewTracked: initial_pageview_tracked == true,
          initialPageKey: initial_page_key
        },
        filters: {
          includePaths: tracking_rules.include_paths,
          excludePaths: tracking_rules.exclude_paths,
          excludeAssets: DEFAULT_EXCLUDE_ASSETS
        },
        debug: false
      }
    end

    def build_external(site:, request:, boundary: nil, host: nil, path: nil)
      return {} if site.blank? || request.blank?

      public_origin = Analytics::Configuration.public_base_url.to_s.strip.presence || request.base_url
      public_origin = public_origin.sub(%r{/+\z}, "")
      tracking_rules = Analytics::TrackingRules.effective(site: site)
      token = Analytics::TrackerSiteToken.generate(
        site: site,
        boundary: boundary,
        host: host,
        path: path,
        mode: "external",
        expires_in: Analytics::TrackerSnippet::EXTERNAL_EXPIRY
      )

      {
        version: VERSION,
        transport: {
          eventsEndpoint: "#{public_origin}/analytics/events"
        },
        site: {
          websiteId: site.public_id,
          token: token,
          domainHint: site.canonical_hostname
        },
        tracking: {
          hashBasedRouting: false
        },
        filters: {
          includePaths: tracking_rules.include_paths,
          excludePaths: tracking_rules.exclude_paths,
          excludeAssets: DEFAULT_EXCLUDE_ASSETS
        },
        debug: false
      }
    end
  end
end
