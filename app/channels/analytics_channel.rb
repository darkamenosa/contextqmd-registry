# frozen_string_literal: true

class AnalyticsChannel < ApplicationCable::Channel
  def subscribed
    unless current_user&.staff?
      reject
      return
    end

    stream = Analytics::LiveState.resolve_subscription_stream(
      params[:subscription_token]
    )

    if stream.blank?
      reject
      return
    end

    stream_from stream
  end
end
