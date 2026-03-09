# frozen_string_literal: true

class Account::Cancellation < ApplicationRecord
  self.table_name = "account_cancellations"

  belongs_to :account
  belongs_to :initiated_by, class_name: "User", optional: true

  validates :account_id, uniqueness: true
end
