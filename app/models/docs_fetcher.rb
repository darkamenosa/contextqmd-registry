# frozen_string_literal: true

# Dispatches to the right fetcher based on source_type.
# Each fetcher returns a CrawlResult with library metadata and pages.
module DocsFetcher
  # Typed errors for retry classification (see crawl-strategy.md).
  # TransientFetchError → job retries (DNS, timeout, 5xx).
  # PermanentFetchError → immediate fail (404, parse error).
  # RateLimitError → job retries with backoff (429, rate-limit 403).
  class TransientFetchError < StandardError; end
  class PermanentFetchError < StandardError; end
  class RateLimitError < TransientFetchError; end

  FETCHERS = {
    "github"    => "DocsFetcher::Git::Github",
    "gitlab"    => "DocsFetcher::Git::Gitlab",
    "bitbucket" => "DocsFetcher::Git::Bitbucket",
    "git"       => "DocsFetcher::Git",
    "website"   => "DocsFetcher::Website",
    "llms_txt"  => "DocsFetcher::LlmsTxt",
    "openapi"   => "DocsFetcher::Openapi"
  }.freeze

  def self.for(source_type)
    klass = FETCHERS[source_type]
    raise ArgumentError, "Unknown source type: #{source_type}" unless klass
    klass.constantize.new
  end

  # Auto-detect source_type from a URL string.
  # Returns one of: "github", "gitlab", "bitbucket", "llms_txt", "openapi", "website"
  def self.detect_source_type(url)
    uri = URI.parse(url.strip)
    host = uri.host&.downcase || ""
    path = uri.path&.downcase || ""

    return "github" if host == "github.com"
    return "gitlab" if gitlab_host?(host)
    return "bitbucket" if host == "bitbucket.org"
    return "llms_txt" if path.match?(/llms(?:-full|-small)?\.txt\z/)
    return "openapi" if openapi_path?(path)

    "website"
  rescue URI::InvalidURIError
    "website"
  end

  def self.gitlab_host?(host)
    host == "gitlab.com" || host.include?("gitlab")
  end
  private_class_method :gitlab_host?

  def self.openapi_path?(path)
    path.match?(/(?:openapi|swagger).*\.(?:json|ya?ml)\z/) ||
      path.match?(/\/(?:openapi|swagger)\z/) ||
      path.match?(/\/api-docs\z/)
  end
  private_class_method :openapi_path?
end
