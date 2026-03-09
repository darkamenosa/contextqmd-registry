# frozen_string_literal: true

require "test_helper"

class CurrentTest < ActiveSupport::TestCase
  test "identity setter clears user outside account scope" do
    identity, account, user = create_tenant(
      email: "current-#{SecureRandom.hex(4)}@example.com",
      name: "Current User"
    )

    Current.with_account(account) do
      Current.identity = identity
      assert_equal user, Current.user
    end

    Current.without_account do
      Current.identity = identity
      assert_nil Current.user
    end
  ensure
    Current.reset
  end
end
