# frozen_string_literal: true

module Api
  module V1
    module Concerns
      module LibraryVersionLookup
        extend ActiveSupport::Concern

        private

          def find_library!
            @library = Library.find_by!(namespace: params[:namespace], name: params[:name])
          rescue ActiveRecord::RecordNotFound
            render_error(code: "not_found", message: "Library not found", status: :not_found)
          end

          def find_library_and_version!
            @library = Library.find_by!(namespace: params[:namespace], name: params[:name])
            @version = @library.versions.find_by!(version: params[:version])
          rescue ActiveRecord::RecordNotFound
            render_error(code: "not_found", message: "Library or version not found", status: :not_found)
          end
      end
    end
  end
end
