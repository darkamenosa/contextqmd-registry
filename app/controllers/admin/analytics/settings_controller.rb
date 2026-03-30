# frozen_string_literal: true

module Admin
  module Analytics
    class SettingsController < BaseController
      def show
        render json: camelize_keys(
          funnels: analytics_funnels_payload,
          settings: analytics_settings_payload,
          paths: analytics_settings_paths
        )
      end

      def update
        permitted = params.expect(
          settings: [
            {
              goals: [],
              allowed_event_props: [],
              tracking_rules: [ { include_paths: [], exclude_paths: [] } ],
              goal_definitions: [ [ :display_name, :event_name, :page_path, :scroll_threshold, { custom_props: {} } ] ]
            }
          ]
        )

        if permitted.key?(:goal_definitions)
          ::Analytics::Goal.sync_from_definitions!(permitted[:goal_definitions], created_by_id: Current.identity&.id)
        elsif permitted.key?(:goals)
          ::Analytics::Goal.sync_from_definitions!(
            ::Analytics::Lists.normalize_strings(permitted[:goals]).map do |name|
              { display_name: name, event_name: name, custom_props: {} }
            end,
            created_by_id: Current.identity&.id
          )
        end

        if permitted.key?(:allowed_event_props)
          normalized_props = ::Analytics::Lists.normalize_strings(permitted[:allowed_event_props])

          if ::Analytics::Current.site.present?
            ::Analytics::AllowedEventProperty.sync_keys!(normalized_props, site: ::Analytics::Current.site)
          else
            ::Analytics::Setting.set_json("allowed_event_props", normalized_props)
          end
        end

        if permitted.key?(:tracking_rules)
          rules = permitted[:tracking_rules].to_h.with_indifferent_access
          ::Analytics::TrackingRules.save!(
            include_paths: rules[:include_paths],
            exclude_paths: rules[:exclude_paths]
          )
        end

        head :no_content
      end
    end
  end
end
