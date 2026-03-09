# frozen_string_literal: true

require "test_helper"

class Identities::SessionsRedirectTest < ActionDispatch::IntegrationTest
  test "public pages are not reused as post login destinations" do
    identity, = create_tenant(
      email: "session-redirect-#{SecureRandom.hex(4)}@example.com",
      name: "Session Redirect"
    )

    get about_path

    assert_response :success

    post identity_session_path, params: {
      identity: {
        email: identity.email,
        password: "password123"
      }
    }

    assert_redirected_to app_path
  end

  test "access tokens page is reused as a post login destination without account memberships" do
    identity = Identity.create!(
      email: "session-access-tokens-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    get app_access_tokens_path

    assert_redirected_to new_identity_session_path

    post identity_session_path, params: {
      identity: {
        email: identity.email,
        password: "password123"
      }
    }

    assert_redirected_to app_access_tokens_path
  end

  test "staff with only cancelled accounts land on app after sign in" do
    identity, account, user = create_tenant(
      email: "session-cancelled-staff-#{SecureRandom.hex(4)}@example.com",
      name: "Cancelled Staff"
    )
    identity.update!(staff: true)
    account.cancel(initiated_by: user)

    post identity_session_path, params: {
      identity: {
        email: identity.email,
        password: "password123"
      }
    }

    assert_redirected_to app_path
  end

  test "signing out clears stale admin destinations before the next sign in" do
    identity, = create_tenant(
      email: "session-sign-out-#{SecureRandom.hex(4)}@example.com",
      name: "Session Sign Out"
    )
    identity.update!(staff: true)

    post identity_session_path, params: {
      identity: {
        email: identity.email,
        password: "password123"
      }
    }

    assert_redirected_to app_path

    get admin_dashboard_path

    assert_response :success

    delete destroy_identity_session_path

    assert_redirected_to root_path

    post identity_session_path, params: {
      identity: {
        email: identity.email,
        password: "password123"
      }
    }

    assert_redirected_to app_path
  end
end
