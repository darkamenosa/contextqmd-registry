# frozen_string_literal: true

module ServerSidePageviewTracking
  extend ActiveSupport::Concern

  EXCLUDED_PREFIXES = Analytics::InternalPaths.server_excluded_prefixes.freeze

  EXCLUDED_PATHS = %w[
    /favicon.ico
    /robots.txt
    /sitemap.xml
    /manifest.json
    /browserconfig.xml
  ].freeze

  included do
    helper_method :analytics_initial_pageview_tracked?,
      :analytics_initial_page_key

    before_action :prepare_server_side_pageview_tracking
    after_action :track_initial_pageview
  end

  private
    def prepare_server_side_pageview_tracking
      return unless analytics_bootstrap_enabled?

      Analytics::BrowserIdentity.ensure!(request, cookies:)
      @analytics_initial_pageview_tracked = true
      @analytics_initial_page_key = analytics_current_page_key
    end

    def track_initial_pageview
      return unless analytics_bootstrap_enabled?
      return if response.redirect?

      ahoy.track(
        "pageview",
        {
          page: request.path,
          url: request.original_url,
          title: try(:page_title).presence || response_title,
          referrer: request.referer.to_s,
          screen_size: nil
        }.compact
      )
    rescue StandardError
      raise if Rails.env.test? || Rails.env.development?
      nil
    end

    def analytics_bootstrap_enabled?
      return false unless Analytics::Configuration.server_visits?
      return false unless server_side_pageview_tracking_enabled_for_request?

      # Be explicit here: HEAD is routed like GET in Rails, but we only want
      # full HTML document renders to bootstrap/track analytics.
      return false unless request.request_method == "GET"
      return false unless request.format.html?
      return false if request.headers["X-Inertia"].present?
      return false if request.xhr?

      path = request.path.to_s.downcase
      return false if EXCLUDED_PREFIXES.any? { |prefix| Analytics::InternalPaths.segment_prefix_match?(path, prefix) }
      return false if EXCLUDED_PATHS.include?(path)
      return false if path.include?("apple-touch-icon")
      return false if speculative_prefetch_request?
      return false if ahoy.exclude?
      return false unless ::Analytics::TrackingRules.trackable_path?(
        path,
        site: ::Analytics::TrackingRules.site_for_request(request),
        include_internal_defaults: false
      )

      true
    end

    def server_side_pageview_tracking_enabled_for_request?
      true
    end

    def speculative_prefetch_request?
      purpose = request.headers["Purpose"].to_s.downcase
      sec_purpose = request.headers["Sec-Purpose"].to_s.downcase
      x_moz = request.headers["X-Moz"].to_s.downcase

      purpose == "prefetch" ||
        sec_purpose.include?("prefetch") ||
        sec_purpose.include?("prerender") ||
        x_moz == "prefetch"
    end

    def analytics_initial_pageview_tracked?
      @analytics_initial_pageview_tracked == true
    end

    def analytics_initial_page_key
      @analytics_initial_page_key
    end

    def analytics_current_page_key
      [ request.path, request.query_string.presence ].compact.join("?")
    end

    def response_title
      return unless response.media_type == "text/html"

      response.body.to_s[/\<title\>(.*?)\<\/title\>/im, 1]&.strip
    rescue StandardError
      nil
    end
end
