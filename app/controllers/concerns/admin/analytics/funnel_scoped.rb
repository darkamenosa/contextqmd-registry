# frozen_string_literal: true

module Admin
  module Analytics
    module FunnelScoped
      extend ActiveSupport::Concern

      included do
        before_action :set_funnel, only: [ :update, :destroy ]
      end

      private
        def set_funnel
          @funnel = ::Analytics::Funnel.effective_find_by_name(params[:id]) || raise(ActiveRecord::RecordNotFound)
        end
    end
  end
end
