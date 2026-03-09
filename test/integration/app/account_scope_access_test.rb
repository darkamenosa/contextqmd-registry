# frozen_string_literal: true

require "test_helper"

class App::AccountScopeAccessTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "unauthenticated users are redirected to login for both valid and unknown account scopes" do
    _identity, account, = create_tenant(
      email: "unknown-scope-guest-#{SecureRandom.hex(4)}@example.com",
      name: "Unknown Scope Guest"
    )

    get app_projects_path(account_id: account.external_account_id)

    assert_redirected_to new_identity_session_path

    get app_projects_path(account_id: 9_999_999)

    assert_redirected_to new_identity_session_path
  ensure
    Current.reset
  end

  test "signed in users get not found for unknown account scopes" do
    identity, _account, = create_tenant(
      email: "unknown-scope-user-#{SecureRandom.hex(4)}@example.com",
      name: "Unknown Scope User"
    )

    sign_in(identity)

    get app_projects_path(account_id: 9_999_999)

    assert_response :not_found
  ensure
    Current.reset
  end

  test "bearer token requests get json not found for unknown account scopes" do
    identity, _account, = create_tenant(
      email: "unknown-scope-token-#{SecureRandom.hex(4)}@example.com",
      name: "Unknown Scope Token"
    )
    _access_token, raw_token = AccessToken.generate(identity: identity, name: "Unknown Scope API")

    get app_projects_path(account_id: 9_999_999), headers: {
      "Authorization" => "Bearer #{raw_token}"
    }

    assert_response :not_found
    assert_equal(
      { "error" => "This account does not exist.", "status" => 404 },
      response.parsed_body
    )
  ensure
    Current.reset
  end
end
