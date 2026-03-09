# frozen_string_literal: true

module App
  class SettingsController < BaseController
    def show
      render inertia: "app/settings/show", props: {
        name: Current.user.name,
        email: Current.identity.email,
        password_changeable: Current.identity.password_set_by_user?
      }
    end

    def update
      if password_change?
        update_password
      else
        update_profile
      end
    end

    def destroy
      if Current.user.owner?
        Current.account.cancel(initiated_by: Current.user)
        redirect_after_account_exit(
          "Account scheduled for deletion. You have 30 days to reactivate."
        )
      else
        Current.user.deactivate
        redirect_after_account_exit("You've left this account.")
      end
    end

    private

      def redirect_after_account_exit(message)
        if Current.identity.accessible_memberships.exists?
          redirect_to app_path, notice: message, status: :see_other
        else
          clear_stored_location_for(:identity)
          sign_out(:identity)
          Current.reset
          redirect_to root_path, notice: message, status: :see_other
        end
      end

      def update_profile
        if Current.user.update(profile_params)
          redirect_to app_settings_path, notice: "Profile updated."
        else
          redirect_to app_settings_path, inertia: inertia_errors(Current.user)
        end
      end

      def update_password
        if Current.identity.update_with_password(password_params)
          bypass_sign_in(Current.identity)
          redirect_to app_settings_path, notice: "Password updated."
        else
          redirect_to app_settings_path, inertia: inertia_errors(Current.identity)
        end
      end

      def password_change?
        params.dig(:settings, :current_password).present?
      end

      def profile_params
        params.expect(settings: [ :name ])
      end

      def password_params
        params.expect(settings: [ :current_password, :password, :password_confirmation ])
      end
  end
end
