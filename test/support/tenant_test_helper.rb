# frozen_string_literal: true

# Test helpers for setting up tenant context (fizzy pattern).
# Include in test classes that need Identity/Account/User context.
module TenantTestHelper
  # Create a complete tenant: Identity + Account + owner User + system User.
  # Returns [identity, account, user].
  def create_tenant(email: "test_#{SecureRandom.hex(4)}@example.com", password: "password123", name: "Test User")
    identity = Identity.create!(email: email, password: password, password_confirmation: password)
    user, account = Account.create_with_user(identity: identity, name: name)
    [ identity, account, user ]
  end

  # Set up Current attributes for tenant-scoped tests.
  def set_tenant_context(identity:, account:)
    Current.account = account
    Current.identity = identity
  end

  # Run a block with tenant context, then reset.
  def with_tenant(identity:, account:, &)
    Current.with_account(account) do
      Current.identity = identity
      yield
    end
  end

  # Sign in with Devise and set tenant context.
  # Requires ActionDispatch::IntegrationTest (for sign_in helper).
  def sign_in_as(identity, account: nil)
    sign_in(identity)
    if account
      Current.account = account
      Current.identity = identity
    end
  end
end
