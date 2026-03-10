# frozen_string_literal: true

# Immutable value object returned by doc fetchers.
# Shared contract between fetchers and CrawlRequest import pipeline.
CrawlResult = Data.define(
  :namespace,     # e.g. "hotwired"
  :name,          # e.g. "turbo-rails"
  :display_name,  # e.g. "Turbo Rails"
  :homepage_url,  # e.g. "https://github.com/hotwired/turbo-rails"
  :aliases,       # e.g. ["turbo-rails", "turbo"]
  :version,       # e.g. nil (will default to "latest")
  :pages,         # array of { page_uid:, path:, title:, url:, content:, headings: }
  :complete       # true = full harvest, false = bounded/partial (don't prune stale pages)
) do
  def initialize(complete: true, **rest)
    super(complete: complete, **rest)
  end
end
