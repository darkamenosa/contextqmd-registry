# frozen_string_literal: true

module DocsFetcher
  # Immutable value object returned by fetchers.
  Result = Data.define(
    :namespace,     # e.g. "hotwired"
    :name,          # e.g. "turbo-rails"
    :display_name,  # e.g. "Turbo Rails"
    :homepage_url,  # e.g. "https://github.com/hotwired/turbo-rails"
    :aliases,       # e.g. ["turbo-rails", "turbo"]
    :version,       # e.g. nil (will default to "latest")
    :pages          # array of { page_uid:, path:, title:, url:, content:, headings: }
  )
end
