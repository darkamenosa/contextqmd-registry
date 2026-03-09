# frozen_string_literal: true

class CrawlRequestsController < InertiaController
  allow_unauthenticated_access only: :index
  disallow_account_scope
  before_action :authenticate_identity!, only: :new

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
    membership = Current.identity.accessible_memberships.includes(:account).first
    redirect_to new_app_crawl_request_path(account_id: membership.account.external_account_id)
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
end
