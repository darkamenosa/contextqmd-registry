# frozen_string_literal: true

module App
  class AccountReactivationsController < InertiaController
    include BlockSearchEngineIndexing
    disallow_account_scope

    def create
      user = Current.identity.users.active.find(params.expect(:membership_id))

      unless user.owner? && user.account.cancelled?
        redirect_to app_path, alert: "Account cannot be reactivated."
        return
      end

      user.account.reactivate
      redirect_to app_dashboard_path(account_id: user.account.external_account_id),
                  notice: "Account reactivated successfully."
    end
  end
end
