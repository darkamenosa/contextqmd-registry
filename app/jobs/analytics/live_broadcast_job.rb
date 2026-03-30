# frozen_string_literal: true

module Analytics
  class LiveBroadcastJob < ApplicationJob
    queue_as :default

    def perform(site_public_id = nil)
      site =
        if site_public_id.present?
          Analytics::Site.find_by(public_id: site_public_id)
        end

      Analytics::LiveState.broadcast_now(site:)
    end
  end
end
