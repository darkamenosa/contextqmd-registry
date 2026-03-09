# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "role values are explicit and stable" do
    assert_equal(
      {
        "owner" => "owner",
        "admin" => "admin",
        "member" => "member",
        "system" => "system"
      },
      User.roles
    )
  end

  test "owner counts as admin" do
    _identity, _account, user = create_tenant(
      email: "owner-admin-#{SecureRandom.hex(4)}@example.com",
      name: "Owner Admin"
    )

    assert_predicate user, :owner?
    assert_predicate user, :admin?
  end

  test "deactivate marks user inactive and clears identity association" do
    identity, _account, user = create_tenant(
      email: "deactivate-user-#{SecureRandom.hex(4)}@example.com",
      name: "Deactivate User"
    )

    user.deactivate

    user.reload
    assert_not_predicate user, :active?
    assert_nil user.identity_id
    assert_equal identity.id, identity.reload.id
  end
end
