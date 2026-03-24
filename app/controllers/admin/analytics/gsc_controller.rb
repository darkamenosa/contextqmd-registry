# frozen_string_literal: true

module Admin
  module Analytics
    class GscController < BaseController
      def show
        render inertia: "admin/analytics/gsc", props: {
          site: site_context,
          user: user_context
        }
      end
    end
  end
end
