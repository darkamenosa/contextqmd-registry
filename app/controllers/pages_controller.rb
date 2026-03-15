# frozen_string_literal: true

class PagesController < InertiaController
  SLUGS = %w[about privacy terms contact].freeze

  allow_unauthenticated_access
  disallow_account_scope

  def show
    render inertia: "pages/#{params[:id]}"
  end
end
