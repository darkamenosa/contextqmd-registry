# frozen_string_literal: true

module Admin
  module Settings
    class AnalyticsController < ::Admin::BaseController
      include ::Admin::Analytics::GoogleSearchConsoleContext
      include ::Admin::Analytics::SiteContext

      def show
        render inertia: "admin/settings/analytics/show", props: {
          site: current_site_context,
          sites: analytics_site_options,
          initialization: analytics_initialization_payload,
          user: user_context,
          funnels: ::Analytics::Current.site.present? ? analytics_funnels_payload : [],
          settings: ::Analytics::Current.site.present? ? analytics_settings_payload : empty_analytics_settings_payload,
          paths: analytics_settings_paths
        }
      end

      def bootstrap
        unless ::Analytics::Configuration.single_site_mode?
          redirect_to admin_settings_analytics_path, alert: "Analytics bootstrap is only available in single-site mode."
          return
        end

        host = ::Analytics::Configuration.default_site_host(request_host: request.host)
        if host.blank?
          redirect_to admin_settings_analytics_path, alert: "Configure a default analytics host before initializing analytics."
          return
        end

        name = ::Analytics::Configuration.default_site_name(request_host: request.host)
        site = ::Analytics::Bootstrap.ensure_default_site!(host:, name:)

        redirect_to ::Analytics::Paths.new(site:, helpers: self).settings,
          notice: "Initialized analytics for #{site.name}."
      end

      private
        def resolve_analytics_site
          resolution = ::Analytics::AdminSiteResolver.resolve(
            request: request,
            explicit_site_id: params[:site]
          )

          ::Analytics::Current.site = resolution&.site
          ::Analytics::Current.site_boundary = resolution&.boundary
        end

        def current_site_context
          ::Analytics::Current.site.present? ? site_context : nil
        end

        def analytics_site_options
          return [] if ::Analytics::Configuration.single_site_mode?

          sites = ::Analytics::Site.active.order(:name).to_a
          return [] if sites.length <= 1

          sites.map do |site|
            {
              id: site.public_id,
              name: site.name,
              domain: site.canonical_hostname,
              settings_path: ::Analytics::Paths.new(site:, helpers: self).settings
            }
          end
        end

        def analytics_initialization_payload
          active_sites = ::Analytics::Site.active.order(:id).to_a

          {
            mode: ::Analytics::Configuration.mode.to_s,
            initialized: active_sites.any?,
            single_site: ::Analytics::Configuration.single_site_mode?,
            can_bootstrap: active_sites.empty? && ::Analytics::Configuration.bootstrappable?(request_host: request.host),
            bootstrap_path: admin_settings_analytics_bootstrap_path,
            suggested_host: ::Analytics::Configuration.default_site_host(request_host: request.host),
            suggested_name: ::Analytics::Configuration.default_site_name(request_host: request.host)
          }
        end

        def empty_analytics_settings_payload
          {
            gsc_configured: false,
            goals: [],
            goal_definitions: [],
            goal_suggestions: [],
            allowed_event_props: [],
            funnel_page_suggestions: [],
            tracker: nil,
            google_search_console: {
              available: ::Analytics::GoogleSearchConsole::Configuration.configured?,
              connected: false,
              configured: false,
              callback_path: ::Analytics::Configuration.google_search_console_callback_path,
              callback_url: "#{request.base_url}#{::Analytics::Configuration.google_search_console_callback_path}",
              properties: []
            }
          }
        end
    end
  end
end
