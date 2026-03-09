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
          result[:records].map { |v| version_json(v) },
          cursor: result[:next_cursor]
        )
      end

      private

        def version_json(version)
          {
            version: version.version,
            channel: version.channel,
            generated_at: version.generated_at&.iso8601,
            manifest_checksum: version.manifest_checksum
          }
        end
    end
  end
end
