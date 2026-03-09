# frozen_string_literal: true

require "test_helper"

class App::BillingAccessTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "owners can access billing" do
    identity, account, = create_tenant(
      email: "owner-billing-#{SecureRandom.hex(4)}@example.com",
      name: "Owner Billing"
    )

    sign_in(identity)

    get app_billing_path(account_id: account.external_account_id)

    assert_response :success
  end

  test "members cannot access billing" do
    _owner_identity, account, = create_tenant(
      email: "billing-owner-#{SecureRandom.hex(4)}@example.com",
      name: "Billing Owner"
    )
    member_identity = Identity.create!(
      email: "billing-member-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    account.users.create!(identity: member_identity, name: "Billing Member", role: :member)

    sign_in(member_identity)

    get app_billing_path(account_id: account.external_account_id)

    assert_response :forbidden
  ensure
    Current.reset
  end

  test "members get json forbidden for billing api requests" do
    _owner_identity, account, = create_tenant(
      email: "billing-owner-json-#{SecureRandom.hex(4)}@example.com",
      name: "Billing Owner Json"
    )
    member_identity = Identity.create!(
      email: "billing-member-json-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    account.users.create!(identity: member_identity, name: "Billing Member Json", role: :member)

    sign_in(member_identity)

    get app_billing_path(account_id: account.external_account_id), as: :json

    assert_response :forbidden
    assert_equal(
      { "error" => "Admin access required.", "status" => 403 },
      response.parsed_body
    )
  ensure
    Current.reset
  end

  test "bearer token billing requests return json forbidden without html fallback" do
    _owner_identity, account, = create_tenant(
      email: "billing-owner-token-#{SecureRandom.hex(4)}@example.com",
      name: "Billing Owner Token"
    )
    member_identity = Identity.create!(
      email: "billing-member-token-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    account.users.create!(identity: member_identity, name: "Billing Member Token", role: :member)
    _access_token, raw_token = AccessToken.generate(identity: member_identity, name: "Billing API")

    get app_billing_path(account_id: account.external_account_id), headers: {
      "Authorization" => "Bearer #{raw_token}"
    }

    assert_response :forbidden
    assert_equal(
      "application/json; charset=utf-8",
      response.headers["Content-Type"]
    )
    assert_equal(
      { "error" => "Admin access required.", "status" => 403 },
      response.parsed_body
    )
  ensure
    Current.reset
  end

  test "bearer token tenant access failures return json forbidden" do
    _owner_identity, account, = create_tenant(
      email: "projects-owner-token-#{SecureRandom.hex(4)}@example.com",
      name: "Projects Owner Token"
    )
    outsider_identity = Identity.create!(
      email: "projects-outsider-token-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    _access_token, raw_token = AccessToken.generate(identity: outsider_identity, name: "Projects API")

    get app_projects_path(account_id: account.external_account_id), headers: {
      "Authorization" => "Bearer #{raw_token}"
    }

    assert_response :forbidden
    assert_equal(
      "application/json; charset=utf-8",
      response.headers["Content-Type"]
    )
    assert_equal(
      { "error" => "You don't have access to this account.", "status" => 403 },
      response.parsed_body
    )
  ensure
    Current.reset
  end
end
