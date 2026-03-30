# frozen_string_literal: true

class Analytics::Configuration
  class << self
    BOOLEAN = ActiveModel::Type::Boolean.new

    def config
      Analytics.config
    end

    def configure
      cfg = config
      yield cfg if block_given?
      cfg
    end

    def mode
      raw = config.mode.presence || "single_site"
      raw.to_s.underscore.to_sym
    end

    def single_site_mode?
      mode != :multi_site
    end

    def default_site
      config.default_site
    end

    def default_site_host(request_host: nil)
      default_site.host.presence || request_host.presence
    end

    def default_site_name(request_host: nil)
      default_site.name.presence || default_site_host(request_host:)
    end

    def bootstrappable?(request_host: nil)
      single_site_mode? && default_site_host(request_host:).present?
    end

    def google_search_console
      config.google_search_console
    end

    def server_visits?
      return true if config.server_visits.nil?

      BOOLEAN.cast(config.server_visits)
    end

    def use_cookies?
      return false if config.use_cookies.nil?

      BOOLEAN.cast(config.use_cookies)
    end

    def use_beacon_for_events?
      return false if config.use_beacon_for_events.nil?

      BOOLEAN.cast(config.use_beacon_for_events)
    end

    def visit_duration_minutes
      config.visit_duration_minutes.presence || 30
    end

    def public_base_url
      config.public_base_url.to_s.strip.presence
    end

    def storage
      config.storage.presence || "postgres"
    end

    def google_search_console_callback_path
      configured = google_search_console.callback_path.presence
      normalized = configured.presence || "/admin/settings/analytics/google_search_console/callback"
      normalized = "/#{normalized}" unless normalized.start_with?("/")
      normalized.start_with?("/admin/") ? normalized : "/admin#{normalized}"
    end
  end
end
