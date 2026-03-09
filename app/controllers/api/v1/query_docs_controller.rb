# frozen_string_literal: true

module Api
  module V1
    class QueryDocsController < BaseController
      skip_before_action :authenticate_api_token!
      include Concerns::LibraryVersionLookup

      before_action :find_library_and_version!

      # POST /api/v1/libraries/:namespace/:name/versions/:version/query
      #
      # Params:
      #   query      - search query string (required)
      #   max_tokens - approximate token budget for response (default: 5000)
      #
      # Returns matching pages packed within the token budget, most relevant first.
      def create
        query = params[:query].to_s.strip
        max_tokens = (params[:max_tokens] || 5000).to_i.clamp(500, 50_000)

        if query.blank?
          return render_error(code: "invalid_query", message: "query parameter is required", status: :unprocessable_entity)
        end

        pages = search_pages(query)
        packed = pack_within_budget(pages, max_tokens)

        render_data(
          packed.map { |p| page_result_json(p[:page], p[:content]) },
          meta: {
            query: query,
            max_tokens: max_tokens,
            results: packed.size,
            total_matches: pages.size
          }
        )
      end

      private

        def search_pages(query)
          @version.pages.search_content(query).limit(50)
        end

        def pack_within_budget(pages, max_tokens)
          packed = []
          token_count = 0

          pages.each do |page|
            content = page.description.to_s
            page_tokens = estimate_tokens(content)

            break if token_count + page_tokens > max_tokens && packed.any?

            packed << { page: page, content: content }
            token_count += page_tokens
          end

          packed
        end

        # Rough token estimate: ~4 chars per token for English text
        def estimate_tokens(text)
          (text.bytesize / 4.0).ceil
        end

        def page_result_json(page, content)
          {
            page_uid: page.page_uid,
            path: page.path,
            title: page.title,
            url: page.url,
            content_md: content
          }
        end
    end
  end
end
