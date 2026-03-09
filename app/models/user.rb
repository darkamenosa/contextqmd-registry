# frozen_string_literal: true

class User < ApplicationRecord
  include Named
  include Role

  belongs_to :identity, optional: true
  belongs_to :account

  validates :name, presence: true
  validates :account_id,
    uniqueness: {
      conditions: -> { where(role: roles[:owner]) },
      message: "already has an owner"
    },
    if: :owner?
  validates :account_id,
    uniqueness: {
      conditions: -> { where(role: roles[:system]) },
      message: "already has a system user"
    },
    if: :system?
  validate :system_user_has_no_identity

  delegate :email, to: :identity, allow_nil: true

  def deactivate
    update!(active: false, identity: nil)
  end

  def reactivate
    update!(active: true)
  end

  private
    def system_user_has_no_identity
      if system? && identity_id.present?
        errors.add(:identity, "must be blank for system users")
      end
    end
end
