# frozen_string_literal: true

module Admin
  module Analytics
    class SearchTermsController < BaseController
      def index
        limit, page = parsed_pagination
        search = normalized_search
        body, status = search_terms_response(@query, limit:, page:, search:)
        render json: body, status: status
      end
    end
  end
end
