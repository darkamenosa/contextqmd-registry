# frozen_string_literal: true

module Admin
  class CustomersController < BaseController
    def index
      base = params[:query].present? ? Identity.search(params[:query]) : Identity.all
      scope = filter_by_status(base)

      pagy, identities = pagy(
        scope.includes(users: { account: :cancellation }).order(sort_column => sort_direction),
        limit: 25
      )

      render inertia: "admin/customers/index", props: {
        customers: identities.map { |i| customer_props(i) },
        pagination: pagination_props(pagy),
        counts: {
          all: base.count,
          active: filter_by_status(base, "active").count,
          cancelled: filter_by_status(base, "cancelled").count,
          suspended: filter_by_status(base, "suspended").count
        },
        filters: {
          status: params[:status] || "all",
          query: params[:query] || "",
          sort: params[:sort] || "created_at",
          direction: params[:direction] || "desc"
        }
      }
    end

    def show
      identity = Identity.includes(users: { account: :cancellation }).find(params[:id])

      render inertia: "admin/customers/show", props: {
        customer: customer_detail_props(identity),
        is_self: identity == Current.identity
      }
    end

    private

      def filter_by_status(scope, status = params[:status])
        case status
        when "active" then scope.admin_active
        when "cancelled" then scope.admin_cancelled
        when "suspended" then scope.suspended
        else scope
        end
      end

      def sort_column
        %w[email created_at].include?(params[:sort]) ? params[:sort] : "created_at"
      end

      def sort_direction
        %w[asc desc].include?(params[:direction]) ? params[:direction] : "desc"
      end

      def customer_props(identity)
        {
          id: identity.id,
          email: identity.email,
          name: identity.display_name,
          auth_method: identity.auth_method,
          staff: identity.staff?,
          status: identity.status,
          accounts_count: identity.users.size,
          created_at: identity.created_at.iso8601
        }
      end

      def customer_detail_props(identity)
        {
          id: identity.id,
          email: identity.email,
          name: identity.display_name,
          auth_method: identity.auth_method,
          staff: identity.staff?,
          status: identity.status,
          suspended_at: identity.suspended_at&.iso8601,
          created_at: identity.created_at.iso8601,
          memberships: identity.users.map { |user| membership_props(user) }
        }
      end

      def membership_props(user)
        cancellation = user.account.cancellation
        {
          id: user.id,
          account_id: user.account.external_account_id,
          account_name: user.account.name,
          role: user.role,
          name: user.name,
          active: user.active?,
          account_cancelled: user.account.cancelled?,
          days_until_deletion: cancellation ? days_remaining(cancellation) : nil,
          can_reactivate: user.owner? && user.account.cancelled?,
          created_at: user.created_at.iso8601
        }
      end

      def days_remaining(cancellation)
        seconds = (cancellation.created_at + Account::Incineratable::INCINERATION_GRACE_PERIOD - Time.current)
        [ seconds.to_i / 86400, 0 ].max
      end
  end
end
