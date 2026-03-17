# frozen_string_literal: true

module Admin
  module VersionScoped
    extend ActiveSupport::Concern

    include LibraryScoped

    included do
      before_action :set_version
    end

    private

      def set_version
        @version = @library.versions.find(params[:version_id] || params[:id])
      end
  end
end
