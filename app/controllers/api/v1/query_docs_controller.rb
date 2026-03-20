# frozen_string_literal: true

module Api
  module V1
    class QueryDocsController < BaseController
      skip_before_action :authenticate_api_token!
      rate_limit to: 60, within: 1.minute, by: -> { request.remote_ip }, only: :create
      include Concerns::LibraryVersionLookup

      before_action :find_library_and_version!

      def create
        query = params.expect(:query).to_s.strip
        max_tokens = (params[:max_tokens] || 5000).to_i.clamp(500, 50_000)
        mode = params[:mode].to_s == "fast" ? :fast : :full

        results = @version.query_docs(query: query, max_tokens: max_tokens, mode: mode)

        render_data(
          results[:results],
          meta: {
            query: query,
            max_tokens: max_tokens,
            mode: mode.to_s,
            results: results[:results].size,
            total_matches: results[:total_matches]
          }
        )
      end
    end
  end
end
