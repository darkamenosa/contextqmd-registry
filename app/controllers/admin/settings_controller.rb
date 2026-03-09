# frozen_string_literal: true

module Admin
  class SettingsController < BaseController
    def show
      render inertia: "admin/settings/show"
    end
  end
end
