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

        # Optional auth: parse token if present but don't reject unauthenticated requests.
        # Use in public controllers that still want to know who the caller is.
        def authenticate_api_token_if_present
          return unless request.headers["Authorization"].present?

          authenticate_with_http_token do |token|
            identity, access_token = AccessToken.authenticate(token)
            if identity&.active_for_authentication? && access_token&.allows?(request.method)
              access_token.touch(:last_used_at)
              Current.identity = identity
              @current_access_token = access_token
            end
          end
        end

        def render_data(data, cursor: nil, meta: {})
          render json: { data: data, meta: meta.merge(cursor: cursor) }
        end

        def render_error(code:, message:, status:)
          render json: { error: { code: code, message: message } }, status: status
        end
    end
  end
end
