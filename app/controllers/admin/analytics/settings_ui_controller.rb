# frozen_string_literal: true

module Admin
  module Analytics
    class SettingsUiController < BaseController
      def show
        render inertia: "admin/analytics/settings", props: {
          site: site_context,
          user: user_context,
          funnels: Funnel.order(:name).pluck(:name, :steps).map { |(name, steps)| { name:, steps: } },
          settings: {
            gsc_configured: AnalyticsSetting.get_bool("gsc_configured", fallback: false)
          }
        }
      end
    end
  end
end
