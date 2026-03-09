# frozen_string_literal: true

module Identities
  class PasswordsController < Devise::PasswordsController
    include InertiaFlash
    rate_limit to: 5, within: 3.minutes, only: :create

    def new
      render inertia: "identities/password/new"
    end

    def edit
      render inertia: "identities/password/edit", props: {
        reset_password_token: current_reset_password_token
      }
    end

    def create
      self.resource = resource_class.send_reset_password_instructions(password_request_params)
      if successfully_sent?(resource)
        redirect_to new_identity_session_path, notice: "Reset instructions sent to your email."
      else
        redirect_to new_identity_password_path, inertia: { errors: resource.errors.to_hash }
      end
    end

    def update
      self.resource = resource_class.reset_password_by_token(password_update_params)
      if resource.errors.empty?
        resource.unlock_access! if unlockable?(resource)
        resource.mark_password_set
        clear_reset_password_token

        if resource.active_for_authentication?
          set_flash_message!(:notice, :updated)
          sign_in(resource_name, resource)
          redirect_to after_authentication_path_for(resource)
        else
          redirect_to new_identity_session_path, alert: I18n.t("devise.failure.#{resource.inactive_message}")
        end
      else
        store_reset_password_token(resource.reset_password_token)
        redirect_to edit_identity_password_path,
          inertia: { errors: resource.errors.to_hash }
      end
    end

    private

      def password_request_params
        params.expect(identity: [ :email ])
      end

      def password_update_params
        params.expect(identity: [ :password, :password_confirmation, :reset_password_token ])
      end

      def current_reset_password_token
        token = params[:reset_password_token].presence || session[:reset_password_token]

        if params[:reset_password_token].present?
          store_reset_password_token(params[:reset_password_token])
        end

        token
      end

      def store_reset_password_token(token)
        session[:reset_password_token] = token
      end

      def clear_reset_password_token
        session.delete(:reset_password_token)
      end

      def assert_reset_token_passed
        if current_reset_password_token.blank?
          set_flash_message(:alert, :no_token)
          redirect_to new_identity_session_path
        end
      end
  end
end
