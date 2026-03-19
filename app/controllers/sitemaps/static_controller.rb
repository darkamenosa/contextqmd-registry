# frozen_string_literal: true

module Sitemaps
  # GET /sitemap_static_1.xml
  class StaticController < BaseController
    def index
      @host = default_host

      if stale?(last_modified: Time.current.beginning_of_day, public: true)
        expires_in 1.day, public: true
        render formats: :xml
      end
    end
  end
end
