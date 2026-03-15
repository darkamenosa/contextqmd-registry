# frozen_string_literal: true

# Recurring job: permanently destroys accounts cancelled beyond the grace period.
# Scheduled via config/recurring.yml (Solid Queue).
class AccountIncinerationJob < ApplicationJob
  retry_on StandardError, wait: 5.minutes, attempts: 10

  def perform(orphaned_account_ids: nil)
    Account.incinerate_now(orphaned_account_ids: orphaned_account_ids)
  end
end
