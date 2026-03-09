# frozen_string_literal: true

module BlockSearchEngineIndexing
  extend ActiveSupport::Concern

  included do
    after_action :block_search_engine_indexing
  end

  private

    def block_search_engine_indexing
      response.headers["X-Robots-Tag"] = "none"
    end
end
