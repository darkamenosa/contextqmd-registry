# frozen_string_literal: true

module App
  class MenusController < InertiaController
    include BlockSearchEngineIndexing
    disallow_account_scope

    def show
      memberships = Current.identity.accessible_memberships.includes(:account)
      cancelled = Current.identity.cancelled_memberships.includes(account: :cancellation)

      if memberships.one? && cancelled.none?
        redirect_to app_dashboard_path(account_id: memberships.first.account.external_account_id)
      elsif memberships.any? || cancelled.any?
        render inertia: "app/menus/show", props: {
          accounts: memberships.map { |u| account_props(u) },
          cancelled_accounts: cancelled.map { |u| cancelled_account_props(u) }
        }
      else
        redirect_to root_path, alert: "You don't have access to any accounts."
      end
    end

    private

      def account_props(user)
        { id: user.account.external_account_id, name: user.account.name, role: user.role }
      end

      def cancelled_account_props(user)
        cancellation = user.account.cancellation
        {
          membership_id: user.id,
          account_id: user.account.external_account_id,
          name: user.account.name,
          role: user.role,
          days_until_deletion: days_remaining(cancellation)
        }
      end

      def days_remaining(cancellation)
        seconds = (cancellation.created_at + Account::Incineratable::INCINERATION_GRACE_PERIOD - Time.current)
        [ seconds.to_i / 86400, 0 ].max
      end
  end
end
