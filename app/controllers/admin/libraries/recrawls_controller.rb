# frozen_string_literal: true

module Admin
  module Libraries
    class RecrawlsController < Admin::BaseController
      def create
        library = Library.find(params[:library_id])
        url = params[:url].presence

        unless url
          redirect_to admin_library_path(id: library.id), alert: "No crawl URL provided."
          return
        end

        # Use the admin's own identity to submit the crawl request
        crawl_request = CrawlRequest.new(
          url: url,
          identity: Current.identity,
          library: library
        )

        if crawl_request.save
          redirect_to admin_library_path(id: library.id), notice: "Re-crawl queued for #{library.display_name}."
        else
          redirect_to admin_library_path(id: library.id),
                      alert: crawl_request.errors.full_messages.join(", ")
        end
      end
    end
  end
end
