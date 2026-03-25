# frozen_string_literal: true

module ServerSidePageviewTracking
  extend ActiveSupport::Concern

  EXCLUDED_PREFIXES = %w[
    /admin
    /app
    /api
    /ahoy
    /rails/
    /assets/
    /up
    /jobs
    /webhooks
    /login
    /logout
    /register
    /password
    /.well-known
  ].freeze

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
    after_action :track_server_side_pageview
  end

  private
    def prepare_server_side_pageview_tracking
      return unless analytics_bootstrap_enabled?

      @analytics_initial_pageview_tracked = true
      @analytics_initial_page_key = analytics_page_key
    end

    def track_server_side_pageview
      return unless analytics_bootstrap_enabled?
      return unless response.media_type == "text/html"
      return if response.redirect?
      return if response.status >= 500

      Current.set(request: request) do
        ahoy.track_visit
        ahoy.track("pageview", server_pageview_properties, time: Time.current)
      end
    end

    def analytics_bootstrap_enabled?
      return false unless Rails.configuration.x.analytics.server_visits

      # Be explicit here: HEAD is routed like GET in Rails, but we only want
      # full HTML document renders to bootstrap/track analytics.
      return false unless request.request_method == "GET"
      return false unless request.format.html?
      return false if request.headers["X-Inertia"].present?
      return false if request.xhr?

      path = request.path.to_s.downcase
      return false if EXCLUDED_PREFIXES.any? { |prefix| path.start_with?(prefix) }
      return false if EXCLUDED_PATHS.include?(path)
      return false if path.include?("apple-touch-icon")
      return false if speculative_prefetch_request?
      return false if ahoy.exclude?

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

    def analytics_page_key
      request.fullpath
    end

    def server_pageview_properties
      {
        page: analytics_page_key,
        url: request.original_url,
        referrer: request.referer.to_s.presence
      }.compact
    end

    def analytics_initial_pageview_tracked?
      @analytics_initial_pageview_tracked == true
    end

    def analytics_initial_page_key
      @analytics_initial_page_key
    end
end
