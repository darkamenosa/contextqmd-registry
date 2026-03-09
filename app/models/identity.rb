# frozen_string_literal: true

class Identity < ApplicationRecord
  include PgSearch::Model

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable,
         :omniauthable, omniauth_providers: [ :google_oauth2 ]

  has_many :users, dependent: :nullify
  has_many :accounts, through: :users
  has_many :access_tokens, dependent: :destroy
  before_destroy :prepare_account_cleanup, prepend: true
  after_destroy_commit :destroy_orphaned_accounts

  # Full-text search: email (primary), user names (secondary)
  # prefix: true allows partial word matching ("tuy" matches "Tuyen")
  pg_search_scope :search,
    against: { email: "A" },
    associated_against: { users: [ :name ] },
    using: { tsearch: { prefix: true } }

  scope :active, -> { where(suspended_at: nil) }
  scope :suspended, -> { where.not(suspended_at: nil) }
  scope :admin_cancelled, lambda {
    active
      .where.not(id: accessible_membership_identity_ids)
      .where(id: cancelled_account_identity_ids)
  }
  scope :admin_active, -> { active.where.not(id: admin_cancelled.select(:id)) }

  def mark_password_set
    update_column(:password_set_by_user, true) unless password_set_by_user?
  end

  def suspend
    update!(suspended_at: Time.current)
  end

  def reactivate
    update!(suspended_at: nil)
  end

  def suspended?
    suspended_at.present?
  end

  def grant_staff_access
    update!(staff: true)
  end

  def revoke_staff_access
    update!(staff: false)
  end

  def deactivate_customer_access
    with_lock do
      memberships = users.lock.includes(:account).to_a
      account_ids = memberships.map(&:account_id).uniq

      memberships.each(&:deactivate)
      update!(suspended_at: Time.current, staff: false)

      cleanup_orphaned_accounts(account_ids)
    end
  end

  def display_name
    users.order(:created_at).first&.name
  end

  def auth_method
    provider.present? ? provider.titleize : "Email"
  end

  def status
    suspended? ? "suspended" : "active"
  end

  def admin_status
    return status if suspended?
    return "cancelled" if account_status == "cancelled"

    status
  end

  def accessible_memberships
    users.active.where.not(account_id: Account::Cancellation.select(:account_id))
  end

  def cancelled_memberships
    users.active.where(account_id: Account::Cancellation.select(:account_id))
  end

  def account_status
    loaded_status = account_status_from_loaded_memberships
    return loaded_status if loaded_status.present?

    if accessible_memberships.exists?
      "active"
    elsif accounts.joins(:cancellation).exists?
      "cancelled"
    else
      "inactive"
    end
  end

  # Block suspended identities from signing in.
  # Membership checks are handled at the route/controller level, not here.
  # This allows staff identities without account memberships to access /admin.
  def active_for_authentication?
    super && !suspended?
  end

  def inactive_message
    suspended? ? :suspended : super
  end

  private
    def self.accessible_membership_identity_ids
      User.active
        .where.not(identity_id: nil)
        .where.not(account_id: Account::Cancellation.select(:account_id))
        .select(:identity_id)
    end

    def self.cancelled_account_identity_ids
      User.joins(account: :cancellation)
        .where.not(identity_id: nil)
        .select(:identity_id)
    end

    def account_status_from_loaded_memberships
      return unless account_memberships_loaded?

      if users.any? { |user| user.active? && !user.account.cancelled? }
        "active"
      elsif users.any? { |user| user.account.cancelled? }
        "cancelled"
      else
        "inactive"
      end
    end

    def account_memberships_loaded?
      association(:users).loaded? &&
        users.all? do |user|
          user.association(:account).loaded? &&
            user.account.association(:cancellation).loaded?
        end
    end

    def cleanup_orphaned_accounts(account_ids)
      if account_ids.present?
        Account.orphaned.where(id: account_ids).find_each(&:incinerate)
      end
    end

    def prepare_account_cleanup
      @account_ids_for_cleanup = users.distinct.pluck(:account_id)
      reassign_cancellation_initiators
      deactivate_users
    end

    def reassign_cancellation_initiators
      memberships = users.includes(account: %i[cancellation users])

      memberships.each do |membership|
        cancellation = membership.account.cancellation

        if cancellation&.initiated_by_id == membership.id
          system_user = membership.account.system_user

          if system_user.present?
            cancellation.update_columns(initiated_by_id: system_user.id, updated_at: Time.current)
          end
        end
      end
    end

    def deactivate_users
      users.find_each(&:deactivate)
    end

    def destroy_orphaned_accounts
      if @account_ids_for_cleanup.present?
        Account.incinerate_orphaned_later(@account_ids_for_cleanup)
      end
    end
end
