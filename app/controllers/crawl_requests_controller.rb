# frozen_string_literal: true

class CrawlRequestsController < InertiaController
  include Pagy::Method

  allow_unauthenticated_access only: :index
  disallow_account_scope
  before_action :authenticate_identity!, only: :new

  def index
    base = CrawlRequest.includes(:library).recent
    active_tab = params[:tab] || "active"

    scope = if active_tab == "completed"
      base.where(status: [ "completed", "failed" ])
    else
      base.where(status: [ "pending", "processing" ])
    end

    pagy, crawl_requests = pagy(:offset, scope, limit: 10)

    render inertia: "crawl-requests/index", props: {
      crawl_requests: crawl_requests.map { |cr| crawl_request_props(cr) },
      pagination: pagination_props(pagy),
      active_tab: active_tab,
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
      props = {
        id: cr.id,
        url: cr.url,
        source_type: cr.source_type,
        status: cr.status,
        library_name: cr.library&.display_name,
        library_slug: cr.library&.slug,
        created_at: cr.created_at.iso8601,
        updated_at: cr.updated_at.iso8601
      }

      if cr.status.in?(%w[pending processing])
        props[:status_message] = cr.status_message
        props[:progress_current] = cr.metadata&.dig("progress_current")
        props[:progress_total] = cr.metadata&.dig("progress_total")
      end

      props
    end
end
