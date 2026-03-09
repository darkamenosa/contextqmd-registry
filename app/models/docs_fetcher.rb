# frozen_string_literal: true

# Dispatches to the right fetcher based on source_type.
# Each fetcher returns a DocsFetcher::Result with library metadata and pages.
module DocsFetcher
  FETCHERS = {
    "github" => "DocsFetcher::Github",
    "gitlab" => "DocsFetcher::Github", # same git-hosting pattern
    "website" => "DocsFetcher::Website",
    "llms_txt" => "DocsFetcher::LlmsTxt",
    "openapi" => "DocsFetcher::Openapi"
  }.freeze

  def self.for(source_type)
    klass = FETCHERS[source_type]
    raise ArgumentError, "Unknown source type: #{source_type}" unless klass
    klass.constantize.new
  end
end
