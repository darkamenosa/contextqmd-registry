# frozen_string_literal: true

module Admin
  module Analytics
    class SettingsUiController < BaseController
      def show
        render inertia: "admin/analytics/settings", props: {
          site: site_context,
          user: user_context,
          funnels: analytics_funnels_payload,
          settings: analytics_settings_payload
        }
      end
    end
  end
end
