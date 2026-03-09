# frozen_string_literal: true

require "test_helper"

class App::SettingsDestroyTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "cancelling the sole account signs the identity out" do
    identity, account, = create_tenant(
      email: "settings-cancel-#{SecureRandom.hex(4)}@example.com",
      name: "Settings Cancel"
    )
    identity.update!(staff: true)

    sign_in(identity)

    delete app_settings_path(account_id: account.external_account_id)

    assert_redirected_to root_path
    assert_equal(
      "Account scheduled for deletion. You have 30 days to reactivate.",
      flash[:notice]
    )
    assert_predicate account.reload, :cancelled?

    get admin_dashboard_path

    assert_redirected_to new_identity_session_path
  ensure
    Current.reset
  end

  test "cancelling the sole account clears stale admin destinations before the next sign in" do
    identity, account, = create_tenant(
      email: "settings-cancel-redirect-#{SecureRandom.hex(4)}@example.com",
      name: "Settings Cancel Redirect"
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

    delete app_settings_path(account_id: account.external_account_id)

    assert_redirected_to root_path

    post identity_session_path, params: {
      identity: {
        email: identity.email,
        password: "password123"
      }
    }

    assert_redirected_to app_path
  ensure
    Current.reset
  end
end
