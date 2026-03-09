# frozen_string_literal: true

require "test_helper"
require "json"

class App::AccessTokensAccessTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "access tokens page shares default account context for the app shell" do
    identity, account, user = create_tenant(
      email: "access-tokens-context-#{SecureRandom.hex(4)}@example.com",
      name: "Access Token Owner"
    )

    sign_in(identity)

    get app_access_tokens_path

    assert_response :success
    assert_nil page_props.dig("props", "currentUser")
    assert_equal(
      account.external_account_id,
      page_props.dig("props", "currentIdentity", "defaultAccountId")
    )
    assert_equal(
      account.name,
      page_props.dig("props", "currentIdentity", "defaultAccountName")
    )
    assert_equal(
      user.role,
      page_props.dig("props", "currentIdentity", "defaultAccountRole")
    )
  ensure
    Current.reset
  end

  test "signed in identities can access access tokens without account memberships" do
    identity = Identity.create!(
      email: "access-tokens-no-membership-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    AccessToken.generate(identity: identity, name: "Existing Token")

    sign_in(identity)

    get app_access_tokens_path

    assert_response :success
  ensure
    Current.reset
  end

  test "signed in identities can access access tokens from account scoped urls" do
    identity, account, = create_tenant(
      email: "access-tokens-scoped-#{SecureRandom.hex(4)}@example.com",
      name: "Scoped Token User"
    )

    sign_in(identity)

    get scoped_app_access_tokens_path(account_id: account.external_account_id)

    assert_response :success
    assert_equal(
      account.external_account_id,
      page_props.dig("props", "currentUser", "accountId")
    )
  ensure
    Current.reset
  end

  test "account scoped access token writes redirect back to the scoped path" do
    identity, account, = create_tenant(
      email: "access-tokens-scoped-write-#{SecureRandom.hex(4)}@example.com",
      name: "Scoped Token Writer"
    )

    sign_in(identity)

    post scoped_app_access_tokens_path(account_id: account.external_account_id), params: {
      access_token: {
        name: "Scoped Token",
        permission: "read"
      }
    }

    assert_redirected_to scoped_app_access_tokens_path(account_id: account.external_account_id)
  ensure
    Current.reset
  end

  private
    def page_props
      page_node = Nokogiri::HTML5(response.body).at_css("script[data-page]")
      JSON.parse(page_node.text)
    end
end
