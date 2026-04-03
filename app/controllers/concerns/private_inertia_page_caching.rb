# frozen_string_literal: true

module PrivateInertiaPageCaching
  extend ActiveSupport::Concern

  private

    # Conditional caching for authenticated Inertia pages.
    #
    # HTML and X-Inertia requests share the same URL but return different
    # response types, so we always vary by X-Inertia and split the validator.
    #
    # Flash is shared on every Inertia response in this app. Returning 304 for a
    # response that originally contained flash would cause the browser to reuse
    # stale flash from its local cache, so any flash-bearing response is forced
    # to no-store.
    def stale_private_inertia_page?(etag:, last_modified: nil, vary_by: nil)
      merge_vary_header!("X-Inertia")
      Array(vary_by).compact.each { |header| merge_vary_header!(header) }

      if flash.to_hash.present?
        response.headers["Cache-Control"] = "no-store"
        return true
      end

      stale?(
        etag: [ request.inertia? ? "inertia" : "html", *Array(etag) ],
        last_modified: last_modified,
        public: false,
        template: false
      )
    end

    def merge_vary_header!(header)
      existing = response.headers["Vary"].to_s.split(",").map(&:strip).reject(&:blank?)
      return if existing.include?(header)

      response.headers["Vary"] = [ *existing, header ].join(", ")
    end
end
