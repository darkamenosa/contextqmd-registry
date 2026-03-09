# frozen_string_literal: true

module Admin
  module Settings
    class BillingsController < Admin::BaseController
      def show
        render inertia: "admin/settings/billing/show"
      end
    end
  end
end
