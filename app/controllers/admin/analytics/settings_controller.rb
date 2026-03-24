# frozen_string_literal: true

module Admin
  module Analytics
    class SettingsController < BaseController
      def show
        render json: camelize_keys(
          funnels: funnels_payload,
          settings: settings_payload
        )
      end

      def update
        permitted = params.expect(settings: [ :gsc_configured ])
        if permitted.key?(:gsc_configured)
          AnalyticsSetting.set_bool("gsc_configured", permitted[:gsc_configured])
        end

        head :no_content
      end

      private
        def funnels_payload
          Funnel.order(:name).pluck(:name, :steps).map { |(name, steps)| { name:, steps: } }
        end

        def settings_payload
          {
            gsc_configured: AnalyticsSetting.get_bool("gsc_configured", fallback: false)
          }
        end
    end
  end
end
