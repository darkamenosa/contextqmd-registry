# frozen_string_literal: true

module Admin
  module Analytics
    class ReportsController < Admin::Analytics::BaseController
      prepend_before_action :ensure_canonical_reports_path, only: :index

      def index
        render inertia: "admin/analytics/reports/index", props: shell_props(@query).merge(
          boot: cache_for([ :reports_boot, request.fullpath ]) { dashboard_boot_payload(@query) }
        )
      end

      private
        def ensure_canonical_reports_path
          ensure_canonical_shell_path!(view: :reports, dialog: params[:dialog])
        end
    end
  end
end
