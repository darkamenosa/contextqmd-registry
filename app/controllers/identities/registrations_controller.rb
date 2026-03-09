# frozen_string_literal: true

module Identities
  class RegistrationsController < Devise::RegistrationsController
    include InertiaFlash
    rate_limit to: 10, within: 3.minutes, only: :create

    def new
      render inertia: "identities/registration/new", props: authentication_page_props
    end

    def create
      build_resource(sign_up_params)
      user_name = params.dig(:user, :name).presence || resource.email.to_s.split("@").first

      Identity.transaction do
        resource.save!
        resource.mark_password_set
        Account.create_with_user(identity: resource, name: user_name)
      end

      set_flash_message!(:notice, :signed_up)
      sign_up(resource_name, resource)
      redirect_to after_sign_up_path_for(resource)
    rescue ActiveRecord::RecordInvalid => error
      clean_up_passwords resource
      redirect_to new_identity_registration_path, inertia: { errors: registration_errors(error) }
    rescue ActiveRecord::RecordNotUnique
      clean_up_passwords resource
      redirect_to new_identity_registration_path,
        inertia: { errors: duplicate_email_error }
    end

    protected

      def after_sign_up_path_for(_resource)
        app_path
      end

    private
      def registration_errors(error)
        errors = resource.errors.to_hash
        errors.merge!(error.record.errors.to_hash) unless error.record == resource

        if email_taken_error?(resource) || email_taken_error?(error.record)
          errors[:email] = duplicate_email_error[:email]
        end

        errors
      end

      def email_taken_error?(record)
        record&.errors&.details&.fetch(:email, [])&.any? { |detail| detail[:error] == :taken }
      end

      def duplicate_email_error
        { email: "We couldn't create your account. Try signing in or resetting your password." }
      end
  end
end
