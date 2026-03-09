# frozen_string_literal: true

require "test_helper"

class App::AccessTokenCsrfTest < ActionDispatch::IntegrationTest
  test "bearer token json writes bypass csrf verification" do
    identity, = create_tenant(
      email: "access-token-csrf-#{SecureRandom.hex(4)}@example.com",
      name: "Access Token CSRF"
    )
    _access_token, raw_token = AccessToken.generate(
      identity: identity,
      name: "Existing API Token",
      permission: :write
    )
    original_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    assert_difference -> { identity.access_tokens.count }, 1 do
      post app_access_tokens_path,
        params: {
          access_token: {
            name: "Generated API Token",
            permission: "read"
          }
        },
        as: :json,
        headers: {
          "Authorization" => "Bearer #{raw_token}"
        }
    end

    assert_response :redirect
  ensure
    ActionController::Base.allow_forgery_protection = original_forgery_protection
    Current.reset
  end
end
