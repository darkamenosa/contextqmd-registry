# frozen_string_literal: true

class Account < ApplicationRecord
  include Cancellable, Incineratable

  has_many :users, dependent: :destroy
  has_many :identities, through: :users

  scope :orphaned, -> { where.not(id: User.where.not(identity_id: nil).select(:account_id)) }

  validates :name, presence: true

  def self.create_with_user(identity:, name:)
    first_name = name.strip.split(" ", 2).first
    transaction do
      account = create!(name: "#{first_name}'s Account", personal: true)
      account.users.create!(name: "System", role: :system)
      user = account.users.create!(identity: identity, name: name, role: :owner)
      [ user, account ]
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
