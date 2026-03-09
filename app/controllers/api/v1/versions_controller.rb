# frozen_string_literal: true

module Api
  module V1
    class VersionsController < BaseController
      include Concerns::LibraryVersionLookup

      before_action :find_library!

      def index
        versions = @library.versions.ordered

        render_data(
          versions.map { |v| version_json(v) },
          meta: { cursor: nil }
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
