# frozen_string_literal: true

# Ensures background jobs run in the correct account context.
# Captures Current.account at enqueue time, restores it at perform time.
module TenantAwareJob
  extend ActiveSupport::Concern

  prepended do
    attr_reader :account
    self.enqueue_after_transaction_commit = true
  end

  def initialize(...)
    super
    @account = Current.account
  end

  def serialize
    super.merge("account" => @account&.to_gid&.to_s)
  end

  def deserialize(job_data)
    super
    if (gid = job_data.fetch("account", nil))
      @account = GlobalID::Locator.locate(gid)
    end
  end

  def perform_now
    if account.present?
      Current.with_account(account) { super }
    else
      super
    end
  end
end

ActiveSupport.on_load(:active_job) do
  prepend TenantAwareJob
end
