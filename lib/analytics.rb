# frozen_string_literal: true

module Analytics
  class Config
    attr_accessor :mode,
      :server_visits,
      :use_cookies,
      :use_beacon_for_events,
      :visit_duration_minutes,
      :public_base_url,
      :storage

    def initialize
      @mode = ENV["ANALYTICS_MODE"].presence || "single_site"
      @server_visits = true
      @use_cookies = false
      @use_beacon_for_events = false
      @visit_duration_minutes = 30
      @public_base_url = ENV["ANALYTICS_PUBLIC_BASE_URL"].presence
      @storage = ENV["ANALYTICS_STORAGE"].presence || "postgres"
      @default_site = normalize_namespace(
        host: ENV["ANALYTICS_HOST"].presence,
        name: ENV["ANALYTICS_SITE_NAME"].presence
      )
      @google_search_console = normalize_namespace(
        client_id: ENV["GOOGLE_SEARCH_CONSOLE_CLIENT_ID"].presence || credentials.dig(:google_search_console, :client_id) || credentials.dig(:analytics, :google_search_console, :client_id),
        client_secret: ENV["GOOGLE_SEARCH_CONSOLE_CLIENT_SECRET"].presence || credentials.dig(:google_search_console, :client_secret) || credentials.dig(:analytics, :google_search_console, :client_secret),
        callback_path: ENV["ANALYTICS_GSC_CALLBACK_PATH"].presence || "/admin/settings/analytics/google_search_console/callback"
      )
    end

    def default_site
      @default_site ||= normalize_namespace
    end

    def default_site=(value)
      @default_site = normalize_namespace(value)
    end

    def google_search_console
      @google_search_console ||= normalize_namespace
    end

    def google_search_console=(value)
      @google_search_console = normalize_namespace(value)
    end

    private
      def credentials
        Rails.application.credentials
      end

      def normalize_namespace(value = nil)
        case value
        when nil
          ActiveSupport::OrderedOptions.new
        when ActiveSupport::OrderedOptions
          value
        when Hash
          ActiveSupport::OrderedOptions.new.tap do |options|
            value.each { |key, nested_value| options[key] = nested_value }
          end
        else
          raise TypeError, "Expected analytics config namespace to be a Hash or OrderedOptions"
        end
      end
  end

  class << self
    def setup
      yield configuration if block_given?
      install!
      configuration
    end

    def configuration
      @configuration ||= Config.new
    end
    alias_method :config, :configuration

    def install!
      require_support_files!
      Analytics::AhoyIntegration.configure!

      return if @controller_hooks_registered

      Rails.application.config.to_prepare do
        Analytics::AhoyIntegration.install_controller_hooks!
      end

      @controller_hooks_registered = true
    end

    def reset_configuration!
      @configuration = Config.new
    end

    private
      def require_support_files!
        return if @support_files_loaded

        require_relative "client_ip"
        require_relative "analytics/country"
        require_relative "analytics/anonymous_identity"
        require_relative "analytics/browser_identity"
        require_relative "analytics/visit_boundary"
        require_relative "analytics/ahoy_server_owned_identity"
        require_relative "analytics/ahoy_store"
        require_relative "analytics/ahoy_integration"
        require_relative "ahoy/store"

        @support_files_loaded = true
      end
  end
end
