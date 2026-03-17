# frozen_string_literal: true

module Admin
  module Users
    class AccountReactivationsController < BaseController
      include Admin::IdentityScoped

      def create
        user = @identity.users.includes(:account).find(params.expect(:membership_id))

        unless user.account.cancelled?
          redirect_to admin_user_path(@identity), alert: "Account is not cancelled."
          return
        end

        user.account.reactivate
        redirect_to admin_user_path(@identity), notice: "Account \"#{user.account.name}\" reactivated."
      end
    end
  end
end
