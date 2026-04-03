# frozen_string_literal: true

class AnalyticsChannel < ApplicationCable::Channel
  def subscribed
    unless current_user&.staff?
      reject
      return
    end

    @analytics_live_stream = Analytics::LiveState.resolve_subscription_stream(
      params[:subscription_token]
    )

    if @analytics_live_stream.blank?
      reject
      return
    end

    stream_from @analytics_live_stream
    @analytics_live_subscription_id = Analytics::LiveState.register_subscription(@analytics_live_stream)
  end

  def unsubscribed
    Analytics::LiveState.unregister_subscription(
      @analytics_live_stream,
      subscription_id: @analytics_live_subscription_id
    )
  end
end
