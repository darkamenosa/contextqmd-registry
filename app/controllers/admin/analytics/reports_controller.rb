# frozen_string_literal: true

module Admin
  module Analytics
    class ReportsController < Admin::Analytics::BaseController
      def index
        render inertia: "admin/analytics/reports/index", props: shell_props(@query)
      end
    end
  end
end
