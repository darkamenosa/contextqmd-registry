# frozen_string_literal: true

module RequestForgeryProtection
  extend ActiveSupport::Concern

  included do
    protect_from_forgery with: :exception
  end

  private

    def verified_request?
      super || bearer_token_json_request?
    end

    def bearer_token_json_request?
      request.format.json? && request.authorization.to_s.start_with?("Bearer")
    end
end
