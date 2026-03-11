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
        return root_path unless request.headers["X-Inertia"].present?

        public_inertia_sign_out_path || new_identity_session_path
      end

    private

      def public_inertia_sign_out_path
        return if request.host == "127.0.0.1"

        referer = request.referer
        return if referer.blank?

        uri = URI.parse(referer)
        return if uri.host.present? && uri.host != request.host

        path = uri.path.presence || root_path
        return unless public_sign_out_path?(path)

        [ path, uri.query.presence ].compact.join("?")
      rescue URI::InvalidURIError
        nil
      end

      def public_sign_out_path?(path)
        route = Rails.application.routes.recognize_path(path, method: :get)

        case route[:controller]
        when "pages"
          true
        when "rankings"
          route[:action] == "index"
        when "libraries"
          %w[index show].include?(route[:action])
        when "libraries/pages"
          route[:action] == "show"
        when "crawl_requests"
          route[:action] == "index"
        when "errors"
          route[:action] == "show"
        else
          false
        end
      rescue ActionController::RoutingError
        false
      end
  end
end
