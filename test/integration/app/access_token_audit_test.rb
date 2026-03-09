# frozen_string_literal: true

require "test_helper"

class App::AccessTokenAuditTest < ActionDispatch::IntegrationTest
  test "read tokens do not update last used at for rejected write requests" do
    identity, = create_tenant(
      email: "access-token-audit-read-#{SecureRandom.hex(4)}@example.com",
      name: "Access Token Audit Read"
    )
    access_token, raw_token = AccessToken.generate(
      identity: identity,
      name: "Read Only API Token",
      permission: :read
    )

    assert_nil access_token.last_used_at

    assert_no_difference -> { identity.access_tokens.count } do
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

    assert_response :unauthorized
    assert_nil access_token.reload.last_used_at
  ensure
    Current.reset
  end

  test "suspended identities do not update last used at for rejected bearer requests" do
    identity, = create_tenant(
      email: "access-token-audit-suspended-#{SecureRandom.hex(4)}@example.com",
      name: "Access Token Audit Suspended"
    )
    access_token, raw_token = AccessToken.generate(
      identity: identity,
      name: "Suspended API Token",
      permission: :write
    )
    identity.suspend

    assert_nil access_token.last_used_at

    get app_access_tokens_path, headers: {
      "Authorization" => "Bearer #{raw_token}"
    }

    assert_response :unauthorized
    assert_nil access_token.reload.last_used_at
  ensure
    Current.reset
  end
end
