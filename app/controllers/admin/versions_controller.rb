# frozen_string_literal: true

module Admin
  class VersionsController < BaseController
    before_action :set_version

    def show
      redirect_to admin_version_pages_path(@version)
    end

    def update
      if @version.update(version_params)
        redirect_to admin_library_path(@version.library), notice: "Version updated."
      else
        redirect_to admin_library_path(@version.library),
          alert: @version.errors.full_messages.join(", ")
      end
    end

    def destroy
      library = @version.library
      @version.destroy!
      redirect_to admin_library_path(library), notice: "Version \"#{@version.version}\" deleted."
    end

    private

      def set_version
        @version = Version.find(params[:id])
      end

      def version_params
        params.expect(version: [ :version, :channel ])
      end
  end
end
