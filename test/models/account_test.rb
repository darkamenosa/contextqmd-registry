# frozen_string_literal: true

require "test_helper"

class AccountTest < ActiveSupport::TestCase
  test "create_with_owner creates owner and system memberships with roles" do
    identity = Identity.create!(
      email: "account-owner-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    account = Account.create_with_owner(
      account: { name: "Account Owner's Account", personal: true },
      owner: { identity: identity, name: "Account Owner" }
    )
    user = account.owner

    assert_equal account, user.account
    assert_predicate user, :owner?
    assert_equal identity, user.identity

    assert_equal 2, account.users.count
    assert_equal "system", account.system_user.role
    assert_nil account.system_user.identity_id
    assert_equal "owner", account.owner.role
  end
end
