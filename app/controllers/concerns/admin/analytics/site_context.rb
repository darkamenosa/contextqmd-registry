# frozen_string_literal: true

module Admin
  module Analytics
    module SiteContext
      extend ActiveSupport::Concern

      SEGMENTS = [
        { id: "all", name: "All visitors" }
      ].freeze

      included do
        before_action :resolve_analytics_site
      end

      private
        def resolve_analytics_site
          resolution = ::Analytics::AdminSiteResolver.resolve!(
            request: request,
            explicit_site_id: params[:site]
          )

          ::Analytics::Current.site = resolution.site
          ::Analytics::Current.site_boundary = resolution.boundary
        end

        def analytics_funnels_payload
          ::Analytics::Funnel.effective_scope.order(:name).pluck(:name, :steps).map { |(name, steps)| { name:, steps: } }
        end

        def site_context
          has_goals = ::Analytics::Goals.available?
          has_props = ::Analytics::Properties.available?
          site = ::Analytics::Current.site

          {
            id: site&.public_id,
            name: site&.name,
            domain: site&.canonical_hostname.presence || request.host,
            timezone: site&.time_zone.presence || Time.zone.name,
            paths: analytics_shell_paths,
            has_goals: has_goals,
            has_props: has_props,
            funnels_available: ::Analytics::Funnel.available?,
            props_available: has_props,
            profiles_available: AnalyticsProfile.available?,
            segments: SEGMENTS,
            flags: {
              dbip: defined?(MaxmindGeo) && MaxmindGeo.available?
            }
          }
        end

        def user_context
          {
            role: "super_admin",
            email: Current.identity&.email
          }
        end

        def analytics_shell_paths
          analytics_paths.shell_paths
        end

        def analytics_paths
          @analytics_paths ||= ::Analytics::Paths.new(site: ::Analytics::Current.site, helpers: self)
        end
    end
  end
end
