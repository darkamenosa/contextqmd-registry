# frozen_string_literal: true

module Admin
  module Analytics
    class SettingsUiController < BaseController
      def show
        redirect_to analytics_settings_paths.fetch(:settings)
      end
    end
  end
end
