# frozen_string_literal: true

class PagesController < InertiaController
  SLUGS = %w[about privacy terms contact].freeze

  allow_unauthenticated_access
  disallow_account_scope

  PAGE_DESCRIPTIONS = {
    "about" => "Learn about ContextQMD — a local-first documentation package system for CLI and MCP tools.",
    "privacy" => "ContextQMD privacy policy. How we handle your data.",
    "terms" => "ContextQMD terms of service.",
    "contact" => "Contact the ContextQMD team."
  }.freeze

  def show
    slug = params[:id]

    merge_vary_header!("X-Inertia")

    if flash.to_hash.present?
      response.headers["Cache-Control"] = "no-store"
    else
      fresh_when(
        etag: [
          request.inertia? ? "inertia" : "html",
          "public-page",
          slug,
          *shared_identity_cache_key_parts
        ],
        public: false,
        template: false
      )
      return if performed?
    end

    render inertia: "pages/#{slug}", props: {
      seo: seo_props(
        title: slug.capitalize,
        description: PAGE_DESCRIPTIONS.fetch(slug, nil),
        url: canonical_url
      )
    }
  end
end
