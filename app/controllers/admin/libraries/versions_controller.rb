# frozen_string_literal: true

module Admin
  module Libraries
    class VersionsController < Admin::BaseController
      include Admin::VersionScoped

      def show
        redirect_to admin_library_version_pages_path(@library, @version)
      end

      def update
        if @version.update(version_params)
          redirect_to admin_library_path(@library), notice: "Version updated."
        else
          redirect_to admin_library_path(@library),
            alert: @version.errors.full_messages.join(", ")
        end
      end

      def destroy
        @version.destroy!
        redirect_to admin_library_path(@library), notice: "Version \"#{@version.version}\" deleted."
      end

      private

        def version_params
          params.expect(version: [ :version, :channel ])
        end
    end
  end
end
