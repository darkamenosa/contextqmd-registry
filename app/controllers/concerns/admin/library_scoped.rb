# frozen_string_literal: true

module Admin
  module LibraryScoped
    extend ActiveSupport::Concern

    included do
      before_action :set_library
    end

    private

      def set_library
        param = params[:library_id] || params[:id]
        @library = if param.to_s.match?(/\A\d+\z/)
          Library.includes(:account, :source_policy, :versions).find(param)
        else
          Library.includes(:account, :source_policy, :versions).find_by!(slug: param)
        end
      end
  end
end
