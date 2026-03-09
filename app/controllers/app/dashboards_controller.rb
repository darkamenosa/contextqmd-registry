# frozen_string_literal: true

module App
  class DashboardsController < BaseController
    def show
      render inertia: "app/dashboard/show"
    end
  end
end
