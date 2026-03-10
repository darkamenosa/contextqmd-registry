# frozen_string_literal: true

module Api
  module V1
    class VersionsController < BaseController
      skip_before_action :authenticate_api_token!
      include Concerns::LibraryVersionLookup
      include Concerns::CursorPaginatable

      before_action :find_library!

      def index
        versions = @library.versions
        versions = versions.where(channel: params[:channel]) if params[:channel].present?

        result = paginate(versions)

        render_data(
          result[:records].map { |v| serialize_version_summary(v) },
          cursor: result[:next_cursor]
        )
      end
    end
  end
end
