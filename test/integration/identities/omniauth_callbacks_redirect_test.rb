# frozen_string_literal: true

require "test_helper"

class Identities::OmniauthCallbacksRedirectTest < ActionDispatch::IntegrationTest
  test "google callback redirects to the stored location" do
    identity, account, = create_tenant(
      email: "oauth-redirect-#{SecureRandom.hex(4)}@gmail.com",
      name: "OAuth Redirect"
    )

    get app_dashboard_path(account_id: account.external_account_id)

    assert_redirected_to new_identity_session_path

    get identity_google_oauth2_omniauth_callback_path, env: {
      "omniauth.auth" => omniauth_auth_hash_for(identity)
    }

    assert_redirected_to app_dashboard_path(account_id: account.external_account_id)
  end

  test "google callback does not reprovision a suspended identity without memberships" do
    identity, _account, = create_tenant(
      email: "oauth-suspended-#{SecureRandom.hex(4)}@gmail.com",
      name: "OAuth Suspended"
    )

    identity.deactivate_customer_access

    assert_predicate identity.reload, :suspended?
    assert_empty identity.users

    assert_no_difference -> { Account.count } do
      assert_no_difference -> { User.count } do
        get identity_google_oauth2_omniauth_callback_path, env: {
          "omniauth.auth" => omniauth_auth_hash_for(identity)
        }
      end
    end

    assert_redirected_to new_identity_session_path
    assert_equal I18n.t("devise.failure.suspended"), flash[:alert]
    assert_empty identity.reload.users
  end

  test "google callback does not link existing identities by non-authoritative email" do
    identity, _account, = create_tenant(
      email: "oauth-custom-domain-#{SecureRandom.hex(4)}@example.com",
      name: "OAuth Custom Domain"
    )

    assert_no_difference -> { Account.count } do
      get identity_google_oauth2_omniauth_callback_path, env: {
        "omniauth.auth" => omniauth_auth_hash_for(identity, authoritative: false)
      }
    end

    assert_redirected_to new_identity_session_path
    assert_equal "Google sign-in failed.", flash[:alert]
    assert_nil identity.reload.provider
    assert_nil identity.uid
  end

  private
    def omniauth_auth_hash_for(identity, authoritative: true)
      raw_info = {
        "email" => identity.email,
        "email_verified" => true
      }
      if authoritative && !identity.email.end_with?("@gmail.com")
        raw_info["hd"] = identity.email.split("@", 2).last
      end

      OmniAuth::AuthHash.new(
        provider: "google_oauth2",
        uid: "google-#{SecureRandom.hex(6)}",
        info: {
          email: identity.email,
          email_verified: true,
          name: identity.display_name
        },
        extra: {
          raw_info:
        }
      )
    end
end
