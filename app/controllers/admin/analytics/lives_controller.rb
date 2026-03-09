# frozen_string_literal: true

module Admin
  module Analytics
    class LivesController < Admin::BaseController
      def show
        render inertia: "admin/analytics/live/show"
      end
    end
  end
end
