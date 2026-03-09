# frozen_string_literal: true

class PagesController < InertiaController
  # Public marketing pages: allow guests and reject accidental /app/:account_id scoping.
  allow_unauthenticated_access
  disallow_account_scope

  def home
    render inertia: "pages/home"
  end

  def about
    render inertia: "pages/about"
  end

  def pricing
    render inertia: "pages/pricing"
  end

  def privacy
    render inertia: "pages/privacy"
  end

  def terms
    render inertia: "pages/terms"
  end

  def contact
    render inertia: "pages/contact"
  end
end
