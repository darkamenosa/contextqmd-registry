# frozen_string_literal: true

module Admin
  class DashboardsController < BaseController
    def show
      render inertia: "admin/dashboard/show"
    end
  end
end
