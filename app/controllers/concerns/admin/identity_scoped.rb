# frozen_string_literal: true

module Admin
  module IdentityScoped
    extend ActiveSupport::Concern

    included do
      before_action :set_identity
    end

    private

      def set_identity
        @identity = Identity.includes(users: { account: :cancellation }).find(params[:user_id] || params[:id])
      end
  end
end
