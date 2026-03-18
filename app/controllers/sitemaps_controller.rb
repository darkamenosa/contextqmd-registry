# frozen_string_literal: true

class SitemapsController < ApplicationController
  include SeoHelper

  allow_unauthenticated_access
  disallow_account_scope

  def show
    @host = "https://#{canonical_host}"
    @libraries = Library.select(:slug, :updated_at).order(:slug)
    @static_pages = %w[about privacy terms contact]

    expires_in 1.hour, public: true
    render formats: :xml
  end
end
