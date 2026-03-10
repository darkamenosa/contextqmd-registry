# frozen_string_literal: true

module Admin
  module Users
    class StaffAccessesController < BaseController
      def create
        identity = Identity.find(params[:user_id])

        identity.grant_staff_access
        redirect_to admin_user_path(identity), notice: "Staff access granted."
      end

      def destroy
        identity = Identity.find(params[:user_id])

        if identity == Current.identity
          redirect_to admin_user_path(identity), alert: "You cannot revoke your own staff access."
          return
        end

        identity.revoke_staff_access
        redirect_to admin_user_path(identity), notice: "Staff access revoked."
      end
    end
  end
end
