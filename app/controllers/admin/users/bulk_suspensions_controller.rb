# frozen_string_literal: true

module Admin
  module Users
    class BulkSuspensionsController < BaseController
      def create
        identities = Identity.where(id: safe_ids)
        count = identities.count
        identities.find_each(&:suspend)

        redirect_to admin_users_path, notice: "#{count} user(s) suspended."
      end

      def destroy
        identities = Identity.where(id: safe_ids)
        count = identities.count
        identities.find_each(&:reactivate)

        redirect_to admin_users_path, notice: "#{count} user(s) reactivated."
      end

      private

        def safe_ids
          params.expect(ids: []).map(&:to_i) - [ Current.identity.id ]
        end
    end
  end
end
