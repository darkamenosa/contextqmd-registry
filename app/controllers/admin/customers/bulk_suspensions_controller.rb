# frozen_string_literal: true

module Admin
  module Customers
    class BulkSuspensionsController < BaseController
      def create
        identities = Identity.where(id: safe_ids)
        count = identities.count
        identities.find_each(&:suspend)

        redirect_to admin_customers_path, notice: "#{count} customer(s) suspended."
      end

      def destroy
        identities = Identity.where(id: safe_ids)
        count = identities.count
        identities.find_each(&:reactivate)

        redirect_to admin_customers_path, notice: "#{count} customer(s) reactivated."
      end

      private

        def safe_ids
          params.expect(ids: []).map(&:to_i) - [ Current.identity.id ]
        end
    end
  end
end
