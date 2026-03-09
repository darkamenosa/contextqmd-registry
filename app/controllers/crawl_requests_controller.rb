# frozen_string_literal: true

class CrawlRequestsController < InertiaController
  allow_unauthenticated_access only: :index
  disallow_account_scope
  before_action :authenticate_identity!, only: [ :new, :create ]

  def index
    crawl_requests = CrawlRequest.includes(:identity, :library).recent.limit(50)

    render inertia: "crawl-requests/index", props: {
      crawl_requests: crawl_requests.map { |cr| crawl_request_props(cr) },
      counts: {
        pending: CrawlRequest.pending.count,
        processing: CrawlRequest.processing.count,
        completed: CrawlRequest.completed.count,
        failed: CrawlRequest.failed.count
      }
    }
  end

  def new
    render inertia: "crawl-requests/new"
  end

  def create
    crawl_request = Current.identity.crawl_requests.new(crawl_request_params)

    if crawl_request.save
      redirect_to crawl_requests_path, notice: "URL submitted for crawling!"
    else
      redirect_to new_crawl_request_path, alert: crawl_request.errors.full_messages.join(", ")
    end
  end

  private

    def crawl_request_props(cr)
      {
        id: cr.id,
        url: cr.url,
        source_type: cr.source_type,
        status: cr.status,
        error_message: cr.error_message,
        library_name: cr.library&.display_name,
        library_slug: cr.library ? "#{cr.library.namespace}/#{cr.library.name}" : nil,
        submitted_by: cr.identity.email,
        created_at: cr.created_at.iso8601,
        updated_at: cr.updated_at.iso8601
      }
    end

    def crawl_request_params
      params.expect(crawl_request: [ :url, :source_type ])
    end
end
