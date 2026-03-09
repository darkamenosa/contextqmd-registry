# frozen_string_literal: true

module App
  class BillingsController < BaseController
    before_action :ensure_admin

    def show
      render inertia: "app/billing/show"
    end
  end
end
