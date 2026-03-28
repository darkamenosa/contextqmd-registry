# frozen_string_literal: true

module Admin
  module Analytics
    class ReferrersController < BaseController
      def index
        source = params[:source].to_s
        return render json: camelize_keys(empty_payload), status: :ok if source.blank?

        # Alias: when source is Google, return Search Terms payload (Plausible-compatible)
        if source.casecmp("Google").zero?
          limit, page = parsed_pagination
          search = normalized_search
          body, status = search_terms_response(@query, limit:, page:, search:)
          return render json: body, status: status
        end

        limit, page = parsed_pagination
        search = normalized_search
        lim_opt = params[:limit].present? ? limit : nil
        page_opt = params[:page].present? ? page : nil
        payload = cache_for([ :referrers, source, lim_opt, page_opt, search, params[:order_by], @query.filter_clauses, @query.time_range_key ]) do
          referrers_payload(@query, source, limit: lim_opt, page: page_opt, search:)
        end
        render json: camelize_keys(payload)
      end

      private
        def empty_payload
          { results: [], metrics: %i[visitors bounce_rate visit_duration], meta: { has_more: false, skip_imported_reason: nil } }
        end
    end
  end
end
