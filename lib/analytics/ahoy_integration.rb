# frozen_string_literal: true

module Analytics
  module AhoyIntegration
    extend self

    VISITS_HOOK_KEY = :@analytics_ahoy_visits_hooks_installed
    EVENTS_HOOK_KEY = :@analytics_ahoy_events_hooks_installed

    def configure!
      Ahoy::Tracker.prepend(Analytics::AhoyServerOwnedIdentity) unless Ahoy::Tracker < Analytics::AhoyServerOwnedIdentity
      Ahoy.user_method = :current_identity

      analytics_config = Analytics.config

      Ahoy.api = true
      Ahoy.cookies = analytics_config.use_cookies ? true : :none
      Ahoy.mask_ips = true
      Ahoy.track_bots = false
      Ahoy.geocode = false
      Ahoy.visit_duration = analytics_config.visit_duration_minutes.to_i.minutes
      Ahoy.quiet = false
      Ahoy.server_side_visits = :when_needed
      Ahoy.exclude_method = method(:exclude_request?)
    end

    def install_controller_hooks!
      install_hooks_for(Ahoy::VisitsController, hook_key: VISITS_HOOK_KEY) if defined?(Ahoy::VisitsController)
      install_hooks_for(Ahoy::EventsController, hook_key: EVENTS_HOOK_KEY) if defined?(Ahoy::EventsController)
    end

    def exclude_request?(controller, request)
      req = request || controller&.request
      return true if req.nil?

      path = req.path.to_s
      return false if path.start_with?("/ahoy", "/analytics")

      Analytics::InternalPaths.server_excluded_prefixes.any? do |prefix|
        path.start_with?(prefix)
      end
    end

    private
      def install_hooks_for(controller_class, hook_key:)
        return if controller_class.instance_variable_defined?(hook_key)

        controller_class.skip_forgery_protection
        controller_class.before_action { Analytics::BrowserIdentity.ensure!(request, cookies:) }
        controller_class.after_action { Analytics::TrackerCorsHeaders.apply!(response.headers) }
        controller_class.around_action do |controller, action|
          ::Analytics::Current.reset
          ::Current.set(request: controller.request) { action.call }
        ensure
          ::Analytics::Current.reset
        end

        controller_class.instance_variable_set(hook_key, true)
      end
  end
end
