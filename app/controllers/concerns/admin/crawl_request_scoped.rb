# frozen_string_literal: true

module Admin
  module CrawlRequestScoped
    extend ActiveSupport::Concern

    included do
      before_action :set_crawl_request
    end

    private

      def set_crawl_request
        @crawl_request = CrawlRequest.includes(:creator, :library, :library_source).find(params[:crawl_request_id] || params[:id])
      end
  end
end
