# frozen_string_literal: true

require "test_helper"
require "json"

class Admin::UsersDeactivationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "suspending a user does not destroy the identity" do
    staff_identity, _staff_account, = create_tenant(
      email: "staff-admin-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Admin"
    )
    staff_identity.update!(staff: true)

    user_identity, account, target_user = create_tenant(
      email: "user-deactivate-#{SecureRandom.hex(4)}@example.com",
      name: "Target User"
    )
    remaining_identity = Identity.create!(
      email: "remaining-user-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    account.users.create!(identity: remaining_identity, name: "Remaining User", role: :member)
    user_identity.update!(staff: true)

    sign_in(staff_identity)

    assert_no_difference -> { Identity.count } do
      post admin_user_suspension_path(user_identity)
    end

    assert_redirected_to admin_user_path(user_identity)
    assert_equal "User suspended.", flash[:notice]
    assert_predicate user_identity.reload, :suspended?
    assert_predicate user_identity, :staff?
    assert_predicate target_user.reload, :active?
    assert_equal user_identity.id, target_user.identity_id
    assert_equal 1, user_identity.users.active.count
    assert Account.exists?(account.id)
  ensure
    Current.reset
  end

  test "show keeps login status active while exposing cancelled account membership" do
    staff_identity, _staff_account, = create_tenant(
      email: "staff-user-show-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Viewer"
    )
    staff_identity.update!(staff: true)

    user_identity, account, target_user = create_tenant(
      email: "user-cancelled-show-#{SecureRandom.hex(4)}@example.com",
      name: "Cancelled User"
    )
    account.cancel(initiated_by: target_user)

    sign_in(staff_identity)

    get admin_user_path(user_identity)

    assert_response :success
    assert_equal "active", page_props.dig("props", "user", "status")
    assert_equal true, page_props.dig("props", "user", "memberships", 0, "active")
    assert_equal true, page_props.dig("props", "user", "memberships", 0, "accountCancelled")
    assert_equal true, page_props.dig("props", "user", "memberships", 0, "canReactivate")
  ensure
    Current.reset
  end

  test "index keeps login status active while cancelled filter still finds cancelled users" do
    staff_identity, _staff_account, = create_tenant(
      email: "staff-user-index-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Index"
    )
    staff_identity.update!(staff: true)

    active_identity, = create_tenant(
      email: "user-active-index-#{SecureRandom.hex(4)}@example.com",
      name: "Active User"
    )
    cancelled_identity, account, target_user = create_tenant(
      email: "user-cancelled-index-#{SecureRandom.hex(4)}@example.com",
      name: "Cancelled User"
    )
    account.cancel(initiated_by: target_user)

    sign_in(staff_identity)

    get admin_users_path

    assert_response :success
    users = page_props.dig("props", "users")
    cancelled_row = users.find { |u| u["id"] == cancelled_identity.id }
    active_row = users.find { |u| u["id"] == active_identity.id }

    assert_equal "active", cancelled_row["status"]
    assert_equal "active", active_row["status"]
    assert_equal 1, page_props.dig("props", "counts", "cancelled")

    get admin_users_path(status: "cancelled")

    assert_response :success
    filtered_users = page_props.dig("props", "users")

    assert_equal [ cancelled_identity.id ], filtered_users.map { |u| u["id"] }
    assert_equal "active", filtered_users.first["status"]
  ensure
    Current.reset
  end

  test "admin can reactivate a cancelled account" do
    staff_identity, _staff_account, = create_tenant(
      email: "staff-account-reactivation-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Reactivator"
    )
    staff_identity.update!(staff: true)

    user_identity, account, target_user = create_tenant(
      email: "user-account-reactivation-#{SecureRandom.hex(4)}@example.com",
      name: "Cancelled User"
    )
    account.cancel(initiated_by: target_user)

    sign_in(staff_identity)

    post admin_user_account_reactivation_path(user_identity), params: {
      membership_id: target_user.id
    }

    assert_redirected_to admin_user_path(user_identity)
    follow_redirect!

    assert_response :success
    assert_not_predicate account.reload, :cancelled?
    assert_equal "active", page_props.dig("props", "user", "status")
    assert_equal false, page_props.dig("props", "user", "memberships", 0, "accountCancelled")
  ensure
    Current.reset
  end

  private
    def page_props
      page_node = Nokogiri::HTML5(response.body).at_css("script[data-page]")
      JSON.parse(page_node.text)
    end
end
