# frozen_string_literal: true

module Admin
  module Libraries
    class RecrawlsController < Admin::BaseController
      include Admin::LibraryScoped

      def create
        url = params[:url].presence

        unless url
          redirect_to admin_library_path(@library), alert: "No crawl URL provided."
          return
        end

        crawl_request = CrawlRequest.new(
          url: url,
          creator: Current.user,
          library: @library
        )

        if crawl_request.save
          redirect_to admin_library_path(@library), notice: "Re-crawl queued for #{@library.display_name}."
        else
          redirect_to admin_library_path(@library),
                      alert: crawl_request.errors.full_messages.join(", ")
        end
      end
    end
  end
end
