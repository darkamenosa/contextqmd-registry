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

  test "authenticated users cannot use login to switch identities" do
    first_identity, = create_tenant(
      email: "session-no-switch-a-#{SecureRandom.hex(4)}@example.com",
      name: "Session No Switch A"
    )
    second_identity, = create_tenant(
      email: "session-no-switch-b-#{SecureRandom.hex(4)}@example.com",
      name: "Session No Switch B"
    )

    post identity_session_path, params: {
      identity: {
        email: first_identity.email,
        password: "password123"
      }
    }

    assert_redirected_to app_path

    assert_no_difference -> { Ahoy::Visit.count } do
      post identity_session_path, params: {
        identity: {
          email: second_identity.email,
          password: "password123"
        }
      }
    end

    assert_redirected_to app_path

    get app_path
    follow_redirect!

    assert_response :success
    assert_equal first_identity.id, controller.current_identity.id
  end

  test "inertia sign out from the home page redirects back to home" do
    identity, = create_tenant(
      email: "session-home-sign-out-#{SecureRandom.hex(4)}@example.com",
      name: "Session Home Sign Out"
    )

    post identity_session_path, params: {
      identity: {
        email: identity.email,
        password: "password123"
      }
    }

    assert_redirected_to app_path

    delete destroy_identity_session_path, headers: {
      "X-Inertia" => "true",
      "X-Requested-With" => "XMLHttpRequest",
      "Referer" => root_url
    }

    assert_redirected_to root_path
  end

  test "inertia sign out from admin falls back to login" do
    identity, = create_tenant(
      email: "session-admin-inertia-sign-out-#{SecureRandom.hex(4)}@example.com",
      name: "Session Admin Inertia Sign Out"
    )
    identity.update!(staff: true)

    post identity_session_path, params: {
      identity: {
        email: identity.email,
        password: "password123"
      }
    }

    assert_redirected_to app_path

    delete destroy_identity_session_path, headers: {
      "X-Inertia" => "true",
      "X-Requested-With" => "XMLHttpRequest",
      "Referer" => admin_dashboard_url
    }

    assert_redirected_to new_identity_session_path
  end

  test "inertia sign out redirects to login to avoid host redirect issues" do
    identity, = create_tenant(
      email: "session-inertia-sign-out-#{SecureRandom.hex(4)}@example.com",
      name: "Session Inertia Sign Out"
    )

    host! "127.0.0.1"

    post identity_session_path, params: {
      identity: {
        email: identity.email,
        password: "password123"
      }
    }

    assert_redirected_to app_path

    delete destroy_identity_session_path, headers: {
      "X-Inertia" => "true",
      "X-Requested-With" => "XMLHttpRequest"
    }

    assert_redirected_to new_identity_session_path
  ensure
    host! "www.example.com"
  end

  test "inertia sign out from home on 127 host keeps the login fallback" do
    identity, = create_tenant(
      email: "session-inertia-home-127-#{SecureRandom.hex(4)}@example.com",
      name: "Session Inertia Home 127"
    )

    host! "127.0.0.1"

    post identity_session_path, params: {
      identity: {
        email: identity.email,
        password: "password123"
      }
    }

    assert_redirected_to app_path

    delete destroy_identity_session_path, headers: {
      "X-Inertia" => "true",
      "X-Requested-With" => "XMLHttpRequest",
      "Referer" => root_url
    }

    assert_redirected_to new_identity_session_path
  ensure
    host! "www.example.com"
  end
end
