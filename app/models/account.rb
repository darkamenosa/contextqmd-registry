# frozen_string_literal: true

class Account < ApplicationRecord
  include Cancellable, Incineratable

  has_many :users, dependent: :destroy
  has_many :identities, through: :users

  SYSTEM_ACCOUNT_NAME = "ContextQMD System"

  scope :orphaned, -> { where.not(id: User.where.not(identity_id: nil).select(:account_id)) }

  validates :name, presence: true

  def self.system
    find_by!(name: SYSTEM_ACCOUNT_NAME)
  end

  def self.create_with_owner(account:, owner:)
    create!(**account).tap do |account|
      account.users.create!(role: :system, name: "System")
      account.users.create!(**owner.with_defaults(role: :owner))
    end
  end

  def self.incinerate_orphaned_later(account_ids)
    if account_ids.present?
      AccountIncinerationJob.perform_later(orphaned_account_ids: account_ids)
    end
  end

  def self.incinerate_orphaned_now(account_ids)
    incinerate_accounts(orphaned.where(id: account_ids))
  end

  def self.incinerate_due_now
    incinerate_accounts(due_for_incineration)
  end

  # Dispatches the right incineration scope and returns failed IDs (if any).
  # Raises on failure so job framework can retry.
  def self.incinerate_now(orphaned_account_ids: nil)
    failed_account_ids = if orphaned_account_ids.present?
      incinerate_orphaned_now(orphaned_account_ids)
    else
      incinerate_due_now
    end

    if failed_account_ids.present?
      raise "Failed to incinerate accounts: #{failed_account_ids.join(', ')}"
    end
  end

  def slug = "/app/#{AccountSlug.encode(external_account_id)}"

  def owner = users.find_by(role: :owner)

  def system_user = users.find_by(role: :system)

  def active?
    !cancelled?
  end

  def self.incinerate_accounts(scope)
    failed_account_ids = []

    scope.find_each do |account|
      begin
        account.incinerate
      rescue StandardError => error
        Rails.logger.error("Failed to incinerate account #{account.id}: #{error.message}")
        Rails.logger.error(error.full_message)
        failed_account_ids << account.id
      end
    end

    failed_account_ids
  end
end
