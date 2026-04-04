# frozen_string_literal: true

module App
  class BaseController < InertiaController
    include BlockSearchEngineIndexing

    private

      # Auto-fill account_id in Rails path helpers for server-side redirects.
      # Client-side navigation uses JS route helpers (js-routes gem) instead.
      def default_url_options
        { account_id: Current.account&.external_account_id }.compact
      end
  end
end
