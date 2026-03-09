# frozen_string_literal: true

module Authentication
  extend ActiveSupport::Concern

  included do
    prepend_before_action :set_current_identity, unless: :devise_controller?
    before_action :store_user_location, if: :storable_location?
    before_action :authenticate_identity!, unless: -> { devise_controller? || authenticated_by_access_token? }
    before_action :require_active_identity, unless: -> { devise_controller? || authenticated_by_access_token? }
    before_action :configure_permitted_parameters, if: :devise_controller?
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :authenticate_identity!, **options
      skip_before_action :require_active_identity, **options
      allow_unauthorized_access(**options)
    end
  end

  private

    def authenticated?
      Current.identity.present?
    end

    def set_current_identity
      authenticate_by_access_token || set_identity_from_session
    end

    def set_identity_from_session
      Current.identity = current_identity if respond_to?(:current_identity)
    end

    def authenticate_by_access_token
      return unless bearer_token_request?

      authenticate_or_request_with_http_token do |token|
        identity, access_token = AccessToken.authenticate(token)
        if identity&.active_for_authentication? && access_token&.allows?(request.method)
          access_token.touch(:last_used_at)
          Current.identity = identity
          @current_access_token = access_token
        end
      end
    end

    def bearer_token_request?
      request.authorization.to_s.start_with?("Bearer")
    end

    def authenticated_by_access_token?
      @current_access_token.present?
    end

    def require_active_identity
      if authenticated? && !Current.identity.active_for_authentication?
        inactive_message = Current.identity.inactive_message
        clear_stored_location_for(:identity)
        sign_out(:identity)
        Current.reset
        redirect_to new_identity_session_path, alert: I18n.t("devise.failure.#{inactive_message}")
      end
    end

    def storable_location?
      request.get? && is_navigational_format? && !devise_controller? && !request.xhr?
    end

    def store_user_location
      store_location_for(:identity, request.fullpath)
    end

    def clear_stored_location_for(resource_or_scope)
      session.delete(stored_location_key_for(resource_or_scope))
    end

    def configure_permitted_parameters
      devise_parameter_sanitizer.permit(:sign_up, keys: [])
      devise_parameter_sanitizer.permit(:account_update, keys: [])
    end

    def after_authentication_path_for(resource)
      stored_location = stored_location_for(resource)

      if stored_location.present? && allowed_stored_location?(stored_location, resource)
        stored_location
      else
        default_after_authentication_path_for(resource)
      end
    end

    def allowed_stored_location?(location, resource)
      if location.start_with?("/admin")
        resource.staff?
      elsif location == app_access_tokens_path
        true
      elsif location == app_path || location.start_with?("/app/")
        resource.accessible_memberships.exists?
      else
        false
      end
    end

    def default_after_authentication_path_for(resource)
      if resource.accessible_memberships.exists? || resource.cancelled_memberships.exists?
        app_path
      elsif resource.staff?
        admin_dashboard_path
      else
        root_path
      end
    end

    def authentication_page_props
      {
        google_oauth_enabled: Devise.omniauth_configs.key?(:google_oauth2),
        google_oauth_authenticity_token: form_authenticity_token(
          form_options: {
            action: identity_google_oauth2_omniauth_authorize_path,
            method: :post
          }
        )
      }
    end
end
