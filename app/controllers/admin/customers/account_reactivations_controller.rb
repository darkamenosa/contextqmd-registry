# frozen_string_literal: true

module Admin
  module Customers
    class AccountReactivationsController < BaseController
      def create
        identity = Identity.find(params[:customer_id])
        user = identity.users.includes(:account).find(params.expect(:membership_id))

        unless user.account.cancelled?
          redirect_to admin_customer_path(identity), alert: "Account is not cancelled."
          return
        end

        user.account.reactivate
        redirect_to admin_customer_path(identity), notice: "Account \"#{user.account.name}\" reactivated."
      end
    end
  end
end
