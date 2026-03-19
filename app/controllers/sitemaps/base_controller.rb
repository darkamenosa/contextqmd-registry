# frozen_string_literal: true

module Sitemaps
  class BaseController < ApplicationController
    include SeoHelper

    allow_unauthenticated_access
    disallow_account_scope

    private

      # Use request.base_url so localhost shows clickable URLs in dev,
      # and production gets the correct host via forwarded headers.
      def default_host
        @default_host ||= request.base_url
      end

      # Percent-encode each segment of a URL path for sitemap <loc> safety
      def encode_path(path)
        path.to_s.split("/").map { |s| CGI.escape(s).gsub("+", "%20") }.join("/")
      end
      helper_method :encode_path
  end
end
