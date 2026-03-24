# frozen_string_literal: true

require Rails.root.join("lib/client_ip")

module CurrentRequest
  extend ActiveSupport::Concern

  included do
    before_action :set_current_request
  end

  private

    def set_current_request
      Current.http_method = request.method
      Current.request_id = request.uuid
      Current.user_agent = request.user_agent
      Current.ip_address = ClientIp.best_effort(request) || request.remote_ip
      Current.referrer = request.referrer
    end
end
