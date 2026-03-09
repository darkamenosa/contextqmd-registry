# frozen_string_literal: true

# Recurring job: permanently destroys accounts cancelled beyond the grace period.
# Scheduled via config/recurring.yml (Solid Queue).
class AccountIncinerationJob < ApplicationJob
  retry_on StandardError, wait: 5.minutes, attempts: 10

  def perform(orphaned_account_ids: nil)
    failed_account_ids =
      if orphaned_account_ids.present?
        Account.incinerate_orphaned_now(orphaned_account_ids)
      else
        Account.incinerate_due_now
      end

    raise "Failed to incinerate accounts: #{failed_account_ids.join(', ')}" if failed_account_ids.present?
  end
end
