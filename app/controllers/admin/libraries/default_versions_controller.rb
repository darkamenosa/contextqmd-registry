# frozen_string_literal: true

module Admin
  module Libraries
    class DefaultVersionsController < Admin::BaseController
      include Admin::LibraryScoped

      def update
        version_tag = params[:version]

        unless @library.versions.exists?(version: version_tag)
          redirect_to admin_library_path(@library), alert: "Version \"#{version_tag}\" not found."
          return
        end

        @library.update!(default_version: version_tag)
        redirect_to admin_library_path(@library), notice: "Default version set to \"#{version_tag}\"."
      end
    end
  end
end
