# frozen_string_literal: true

module Admin
  module Customers
    class SuspensionsController < BaseController
      def create
        identity = Identity.find(params[:customer_id])

        if identity == Current.identity
          redirect_to admin_customer_path(identity), alert: "You cannot suspend your own account."
          return
        end

        identity.suspend
        redirect_to admin_customer_path(identity), notice: "Customer suspended."
      end

      def destroy
        identity = Identity.find(params[:customer_id])

        identity.reactivate
        redirect_to admin_customer_path(identity), notice: "Customer unsuspended."
      end
    end
  end
end
