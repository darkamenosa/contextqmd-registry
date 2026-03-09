# frozen_string_literal: true

module Identities
  class SessionsController < Devise::SessionsController
    include InertiaFlash
    rate_limit to: 10, within: 3.minutes, only: :create

    def new
      render inertia: "identities/session/new", props: authentication_page_props
    end

    def create
      self.resource = warden.authenticate!(auth_options)
      set_flash_message!(:notice, :signed_in)
      sign_in(resource_name, resource)
      redirect_to after_sign_in_path_for(resource)
    end

    def destroy
      clear_stored_location_for(resource_name)
      signed_out = (Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name))
      set_flash_message!(:notice, :signed_out) if signed_out
      redirect_to after_sign_out_path_for(resource_name), status: :see_other
    end

    protected

      def after_sign_in_path_for(resource)
        after_authentication_path_for(resource)
      end

      def after_sign_out_path_for(_resource)
        root_path
      end
  end
end
