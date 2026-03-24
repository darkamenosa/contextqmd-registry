# frozen_string_literal: true

class AnalyticsUpdateJob < ApplicationJob
  queue_as :default

  # Broadcast a lightweight Live View payload
  def perform
    payload = AnalyticsLiveStats.build(now: Time.zone.now)
    ActionCable.server.broadcast("analytics", payload)
  end
end
