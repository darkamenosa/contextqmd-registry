# frozen_string_literal: true

module Identities
  class SessionsController < Devise::SessionsController
    PUBLIC_SIGN_OUT_PATH_PATTERNS = [
      %r{\A/\z},
      %r{\A/(?:about|privacy|terms|contact)\z},
      %r{\A/rankings\z},
      %r{\A/libraries\z},
      %r{\A/libraries/(?!new\z)[^/]+\z},
      %r{\A/libraries/[^/]+/versions/[^/]+/pages/.+\z},
      %r{\A/crawl\z},
      %r{\A/errors/\d+\z}
    ].freeze

    include InertiaFlash
    rate_limit to: 10, within: 3.minutes, only: :create

    def new
      render inertia: "identities/session/new", props: authentication_page_props
    end

    def create
      previous_identity_id = warden.user(resource_name)&.id
      self.resource = warden.authenticate!(auth_options)
      set_flash_message!(:notice, :signed_in)
      sign_in(resource_name, resource)
      Analytics::VisitBoundary.mark_sign_in!(
        session: session,
        previous_identity_id: previous_identity_id,
        next_identity_id: resource.id
      )
      redirect_to after_sign_in_path_for(resource)
    end

    def destroy
      previous_identity_id = current_identity&.id
      clear_stored_location_for(resource_name)
      signed_out = (Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name))
      Analytics::VisitBoundary.mark_sign_out!(session: session, identity_id: previous_identity_id) if signed_out
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
        return false unless path.start_with?("/")

        normalized_path = path == "/" ? path : path.delete_suffix("/")

        PUBLIC_SIGN_OUT_PATH_PATTERNS.any? { |pattern| pattern.match?(normalized_path) }
      end
  end
end
