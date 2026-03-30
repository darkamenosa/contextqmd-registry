# frozen_string_literal: true

module Admin
  module Analytics
    class LiveController < BaseController
      prepend_before_action :ensure_canonical_live_path, only: :show

      def show
        render inertia: "admin/analytics/live/show", props: {
          site: site_context,
          live_subscription_token: ::Analytics::LiveState.subscription_token,
          "initialStats" => ::Analytics::LiveState.build(now: Time.zone.now, camelize: false)
        }
      end

      private
        def ensure_canonical_live_path
          ensure_canonical_shell_path!(view: :live)
        end
    end
  end
end
