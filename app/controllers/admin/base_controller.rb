# frozen_string_literal: true

module Admin
  class BaseController < InertiaController
    include Pagy::Method
    include BlockSearchEngineIndexing
    disallow_account_scope
    before_action :ensure_staff

    private

      # Pagination helper - returns hash for Inertia props
      # Usage: pagination_props(pagy) => { page: 1, perPage: 25, total: 100, ... }
      def pagination_props(pagy)
        {
          page: pagy.page,
          per_page: pagy.limit,
          total: pagy.count,
          pages: pagy.last,
          from: pagy.from,
          to: pagy.to,
          has_previous: pagy.previous.present?,
          has_next: pagy.next.present?
        }
      end
  end
end
