# frozen_string_literal: true

module Admin
  class WebhooksController < BaseController
    def index
      render inertia: "admin/webhooks/index"
    end
  end
end
