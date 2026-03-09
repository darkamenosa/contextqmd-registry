# frozen_string_literal: true

require "test_helper"
require "json"

class Admin::CustomersDeactivationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "suspending a customer does not destroy the identity" do
    staff_identity, _staff_account, = create_tenant(
      email: "staff-admin-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Admin"
    )
    staff_identity.update!(staff: true)

    customer_identity, account, customer_user = create_tenant(
      email: "customer-deactivate-#{SecureRandom.hex(4)}@example.com",
      name: "Customer User"
    )
    remaining_identity = Identity.create!(
      email: "remaining-customer-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    account.users.create!(identity: remaining_identity, name: "Remaining Customer", role: :member)
    customer_identity.update!(staff: true)

    sign_in(staff_identity)

    assert_no_difference -> { Identity.count } do
      post admin_customer_suspension_path(customer_identity)
    end

    assert_redirected_to admin_customer_path(customer_identity)
    assert_equal "Customer suspended.", flash[:notice]
    assert_predicate customer_identity.reload, :suspended?
    assert_predicate customer_identity, :staff?
    assert_predicate customer_user.reload, :active?
    assert_equal customer_identity.id, customer_user.identity_id
    assert_equal 1, customer_identity.users.active.count
    assert Account.exists?(account.id)
  ensure
    Current.reset
  end

  test "show keeps login status active while exposing cancelled account membership" do
    staff_identity, _staff_account, = create_tenant(
      email: "staff-customer-show-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Viewer"
    )
    staff_identity.update!(staff: true)

    customer_identity, account, customer_user = create_tenant(
      email: "customer-cancelled-show-#{SecureRandom.hex(4)}@example.com",
      name: "Cancelled Customer"
    )
    account.cancel(initiated_by: customer_user)

    sign_in(staff_identity)

    get admin_customer_path(customer_identity)

    assert_response :success
    assert_equal "active", page_props.dig("props", "customer", "status")
    assert_equal true, page_props.dig("props", "customer", "memberships", 0, "active")
    assert_equal true, page_props.dig("props", "customer", "memberships", 0, "accountCancelled")
    assert_equal true, page_props.dig("props", "customer", "memberships", 0, "canReactivate")
  ensure
    Current.reset
  end

  test "index keeps login status active while cancelled filter still finds cancelled customers" do
    staff_identity, _staff_account, = create_tenant(
      email: "staff-customer-index-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Index"
    )
    staff_identity.update!(staff: true)

    active_identity, = create_tenant(
      email: "customer-active-index-#{SecureRandom.hex(4)}@example.com",
      name: "Active Customer"
    )
    cancelled_identity, account, customer_user = create_tenant(
      email: "customer-cancelled-index-#{SecureRandom.hex(4)}@example.com",
      name: "Cancelled Customer"
    )
    account.cancel(initiated_by: customer_user)

    sign_in(staff_identity)

    get admin_customers_path

    assert_response :success
    customers = page_props.dig("props", "customers")
    cancelled_row = customers.find { |customer| customer["id"] == cancelled_identity.id }
    active_row = customers.find { |customer| customer["id"] == active_identity.id }

    assert_equal "active", cancelled_row["status"]
    assert_equal "active", active_row["status"]
    assert_equal 1, page_props.dig("props", "counts", "cancelled")

    get admin_customers_path(status: "cancelled")

    assert_response :success
    filtered_customers = page_props.dig("props", "customers")

    assert_equal [ cancelled_identity.id ], filtered_customers.map { |customer| customer["id"] }
    assert_equal "active", filtered_customers.first["status"]
  ensure
    Current.reset
  end

  test "admin can reactivate a cancelled account" do
    staff_identity, _staff_account, = create_tenant(
      email: "staff-account-reactivation-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Reactivator"
    )
    staff_identity.update!(staff: true)

    customer_identity, account, customer_user = create_tenant(
      email: "customer-account-reactivation-#{SecureRandom.hex(4)}@example.com",
      name: "Cancelled Customer"
    )
    account.cancel(initiated_by: customer_user)

    sign_in(staff_identity)

    post admin_customer_account_reactivation_path(customer_identity), params: {
      membership_id: customer_user.id
    }

    assert_redirected_to admin_customer_path(customer_identity)
    follow_redirect!

    assert_response :success
    assert_not_predicate account.reload, :cancelled?
    assert_equal "active", page_props.dig("props", "customer", "status")
    assert_equal false, page_props.dig("props", "customer", "memberships", 0, "accountCancelled")
  ensure
    Current.reset
  end

  private
    def page_props
      page_node = Nokogiri::HTML5(response.body).at_css("script[data-page]")
      JSON.parse(page_node.text)
    end
end
