# frozen_string_literal: true

require "test_helper"

class IdentityTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "deactivate_customer_access suspends identity and deactivates memberships" do
    identity, account, owner = create_tenant(
      email: "deactivate-customer-#{SecureRandom.hex(4)}@example.com",
      name: "Customer Owner"
    )
    remaining_identity = Identity.create!(
      email: "remaining-member-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    account.users.create!(identity: remaining_identity, name: "Remaining Member", role: :member)

    second_account = Account.create!(name: "Second Account", personal: false)
    second_account.users.create!(name: "System", role: :system)
    second_membership = second_account.users.create!(
      identity: identity,
      name: "Customer Owner",
      role: :owner
    )

    identity.update!(staff: true)

    identity.deactivate_customer_access

    assert_predicate identity.reload, :suspended?
    assert_not_predicate identity, :staff?
    assert_not_predicate owner.reload, :active?
    assert_nil owner.identity_id
    assert_not User.exists?(second_membership.id)
    assert_empty identity.users.active
    assert_equal account.id, owner.account_id
    assert Account.exists?(account.id)
    assert_not Account.exists?(second_account.id)
  ensure
    Current.reset
  end

  test "destroying cancelled account owner identity reassigns cancellation and keeps account when other members exist" do
    owner_identity, account, owner_user = create_tenant(
      email: "owner-#{SecureRandom.hex(4)}@example.com",
      name: "Owner User"
    )
    member_identity = Identity.create!(
      email: "member-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    account.users.create!(identity: member_identity, name: "Member User", role: :member)

    Current.with_account(account) do
      Current.identity = owner_identity
      account.cancel(initiated_by: owner_user)
    end

    assert_nothing_raised do
      owner_identity.destroy!
    end

    assert Account.exists?(account.id)
    assert_equal account.system_user, account.reload.cancellation.initiated_by
    assert User.exists?(owner_user.id)
    assert_nil owner_user.reload.identity_id
    assert_not_predicate owner_user, :active?
  ensure
    Current.reset
  end

  test "destroying sole identity also removes now-orphaned account" do
    identity, account, user = create_tenant(
      email: "solo-#{SecureRandom.hex(4)}@example.com",
      name: "Solo User"
    )
    original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test

    Current.with_account(account) do
      Current.identity = identity
      account.cancel(initiated_by: user)
    end

    assert_enqueued_jobs 1, only: AccountIncinerationJob do
      identity.destroy!
    end

    perform_enqueued_jobs only: AccountIncinerationJob

    assert_not Account.exists?(account.id)
  ensure
    clear_enqueued_jobs
    clear_performed_jobs
    ActiveJob::Base.queue_adapter = original_queue_adapter
    Current.reset
  end
end
