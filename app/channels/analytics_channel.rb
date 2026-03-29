# frozen_string_literal: true

class AnalyticsChannel < ApplicationCable::Channel
  def subscribed
    unless current_user&.staff?
      reject
      return
    end

    stream_from Analytics::LiveState.broadcast_stream(site: resolved_site)
  end

  private
    def resolved_site
      site_id = params[:site_id].presence
      return nil if site_id.blank?

      Analytics::Site.find_by(public_id: site_id)
    end
end
