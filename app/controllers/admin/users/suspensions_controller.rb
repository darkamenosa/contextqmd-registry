# frozen_string_literal: true

module Admin
  module Users
    class SuspensionsController < BaseController
      include Admin::IdentityScoped

      def create
        if @identity == Current.identity
          redirect_to admin_user_path(@identity), alert: "You cannot suspend your own account."
          return
        end

        @identity.suspend
        redirect_to admin_user_path(@identity), notice: "User suspended."
      end

      def destroy
        @identity.reactivate
        redirect_to admin_user_path(@identity), notice: "User unsuspended."
      end
    end
  end
end
