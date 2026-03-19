# frozen_string_literal: true

module Sitemaps
  # GET /sitemap_libraries_1.xml?from=1&to=5000
  class LibrariesController < BaseController
    def index
      return head(:not_found) unless params[:from].present? && params[:to].present?

      @host = default_host

      scope = Library.not_cancelled
                     .where("libraries.id >= ?", params[:from].to_i)
                     .where("libraries.id <= ?", params[:to].to_i)
                     .order(:id)

      latest_update = scope.maximum(:updated_at) || Time.current

      if stale?(last_modified: latest_update, public: true)
        @libraries = scope.select(:id, :slug, :updated_at)
        expires_in 1.hour, public: true
        render formats: :xml
      end
    end
  end
end
