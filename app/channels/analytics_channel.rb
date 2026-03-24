# frozen_string_literal: true

class AnalyticsChannel < ApplicationCable::Channel
  def subscribed
    unless current_user&.staff?
      reject
      return
    end

    stream_from "analytics"
  end
end
