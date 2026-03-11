# frozen_string_literal: true

class CrawlRequestsController < InertiaController
  allow_unauthenticated_access only: :index
  disallow_account_scope
  before_action :authenticate_identity!, only: :new

  def index
    crawl_requests = CrawlRequest.includes(:library).recent.limit(50)

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
    membership = current_identity_default_membership
    if membership
      redirect_to new_app_crawl_request_path(account_id: membership.account.external_account_id)
    else
      redirect_to root_path, alert: "Please complete your account setup first."
    end
  end

  private

    def crawl_request_props(cr)
      {
        id: cr.id,
        url: cr.url,
        source_type: cr.source_type,
        status: cr.status,
        library_name: cr.library&.display_name,
        library_slug: cr.library ? "#{cr.library.namespace}/#{cr.library.name}" : nil,
        created_at: cr.created_at.iso8601,
        updated_at: cr.updated_at.iso8601
      }
    end
end
