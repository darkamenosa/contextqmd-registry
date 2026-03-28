# frozen_string_literal: true

module Admin
  module Analytics
    class LiveController < ::Admin::BaseController
      def show
        render inertia: "admin/analytics/live/show", props: {
          "initialStats" => ::Analytics::LiveState.build(now: Time.zone.now, camelize: false)
        }
      end
    end
  end
end
