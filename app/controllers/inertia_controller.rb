# frozen_string_literal: true

class InertiaController < ApplicationController
  include InertiaFlash
  include InertiaUtils

  # Share data with all Inertia responses
  inertia_share current_user: -> { current_user_props }
  inertia_share current_identity: -> { current_identity_props }
  inertia_share request_context: -> { request_context_props }

  private

    def current_user_props
      return nil unless Current.user && Current.account

      {
        id: Current.user.id,
        name: Current.user.name,
        email: Current.user.email,
        role: Current.user.role,
        staff: Current.identity&.staff? || false,
        account_id: Current.account.external_account_id,
        account_name: Current.account.name
      }
    end

    def current_identity_props
      return nil unless Current.identity

      default_membership = current_identity_default_membership

      {
        id: Current.identity.id,
        name: Current.identity.display_name,
        email: Current.identity.email,
        staff: Current.identity.staff?,
        default_account_id: default_membership&.account&.external_account_id,
        default_account_name: default_membership&.account&.name,
        default_account_role: default_membership&.role
      }
    end

    def current_identity_default_membership
      Current.identity.accessible_memberships
        .includes(:account)
        .by_role_priority
        .order(created_at: :asc)
        .first
    end

    def request_context_props
      {
        request_id: Current.request_id,
        timezone: Time.zone.tzinfo.name,
        platform: platform.type
      }
    end
end
