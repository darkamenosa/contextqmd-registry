# frozen_string_literal: true

module Analytics
  class LiveBroadcastJob < ApplicationJob
    queue_as :default

    def perform
      Analytics::LiveState.broadcast_now
    end
  end
end
