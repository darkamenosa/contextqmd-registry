# frozen_string_literal: true

module Api
  module V1
    class BaseController < ActionController::API
      include ActionController::HttpAuthentication::Token::ControllerMethods

      before_action :authenticate_api_token!

      private
        def authenticate_api_token!
          authenticate_or_request_with_http_token do |token|
            identity, access_token = AccessToken.authenticate(token)
            if identity&.active_for_authentication? && access_token&.allows?(request.method)
              access_token.touch(:last_used_at)
              Current.identity = identity
              @current_access_token = access_token
            end
          end
        end

        def render_data(data, meta: {})
          render json: { data: data, meta: meta }
        end

        def render_error(code:, message:, status:)
          render json: { error: { code: code, message: message } }, status: status
        end
    end
  end
end
