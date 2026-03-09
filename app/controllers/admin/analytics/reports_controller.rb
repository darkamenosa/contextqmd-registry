# frozen_string_literal: true

module Admin
  module Analytics
    class ReportsController < Admin::BaseController
      def index
        render inertia: "admin/analytics/reports/index"
      end
    end
  end
end
