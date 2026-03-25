# frozen_string_literal: true

module Admin
  module Analytics
    class SettingsController < BaseController
      def show
        render json: camelize_keys(
          funnels: analytics_funnels_payload,
          settings: analytics_settings_payload
        )
      end

      def update
        permitted = params.expect(
          settings: [
            :gsc_configured,
            { goals: [], allowed_event_props: [], goal_definitions: [ [ :display_name, :event_name, :page_path, :scroll_threshold, { custom_props: {} } ] ] }
          ]
        )
        if permitted.key?(:gsc_configured)
          AnalyticsSetting.set_bool("gsc_configured", permitted[:gsc_configured])
        end

        if permitted.key?(:goal_definitions)
          Goal.sync_from_definitions!(permitted[:goal_definitions], created_by_id: Current.identity&.id)
          AnalyticsSetting.set_bool("goals_managed", true)
        elsif permitted.key?(:goals)
          Goal.sync_from_definitions!(
            Ahoy::Visit.normalize_string_list(permitted[:goals]).map do |name|
              { display_name: name, event_name: name, custom_props: {} }
            end,
            created_by_id: Current.identity&.id
          )
          AnalyticsSetting.set_bool("goals_managed", true)
        end

        if permitted.key?(:allowed_event_props)
          AnalyticsSetting.set_json("allowed_event_props", Ahoy::Visit.normalize_string_list(permitted[:allowed_event_props]))
        end

        head :no_content
      end
    end
  end
end
