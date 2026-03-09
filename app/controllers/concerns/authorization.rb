# frozen_string_literal: true

module Authorization
  extend ActiveSupport::Concern

  included do
    before_action :ensure_valid_account_scope, if: :authenticated_account_access?
    before_action :ensure_can_access_account, if: :authenticated_account_access?
  end

  class_methods do
    def allow_unauthorized_access(**options)
      skip_before_action :ensure_can_access_account, raise: false, **options
    end

    def require_access_without_a_user(**options)
      allow_unauthorized_access(**options)
      before_action :redirect_existing_user, **options
    end

    def disallow_account_scope(**options)
      allow_unauthorized_access(**options)
      before_action(:redirect_tenanted_request, **options)
    end
  end

  private

    def ensure_admin
      render_error_response(403, "Forbidden", "Admin access required.") unless Current.user&.admin?
    end

    def ensure_staff
      render_error_response(403, "Forbidden", "Staff access required.") unless Current.identity&.staff?
    end

    def authenticated_account_access?
      requested_account_scope? && authenticated?
    end

    def ensure_can_access_account
      unless Current.account&.active? && Current.user&.active?
        if api_request?
          render_api_error(:forbidden, "You don't have access to this account.")
        elsif request.format.html?
          redirect_to app_path, alert: "You don't have access to this account."
        else
          head :forbidden
        end
      end
    end

    def ensure_valid_account_scope
      render_error_response(404, "Not Found", "This account does not exist.") unless Current.account.present?
    end

    def redirect_existing_user
      return unless Current.user.present?

      if Current.account.present?
        redirect_to app_dashboard_path(account_id: Current.account.external_account_id)
      else
        redirect_to app_path
      end
    end

    def redirect_tenanted_request
      render_error_response(404, "Not Found", "This page is not available in account scope.") if Current.account.present?
    end

    def requested_account_scope?
      request.env["contextqmd_registry.account_id"].present?
    end
end
