# frozen_string_literal: true

# Dispatches to the right fetcher based on source_type.
# Each fetcher returns a DocsFetcher::Result with library metadata and pages.
module DocsFetcher
  FETCHERS = {
    "github" => "DocsFetcher::Github",
    "gitlab" => "DocsFetcher::Gitlab",
    "website" => "DocsFetcher::Website",
    "llms_txt" => "DocsFetcher::LlmsTxt",
    "openapi" => "DocsFetcher::Openapi"
  }.freeze

  GITHUB_HOSTS = %w[github.com].freeze
  GITLAB_HOSTS = %w[gitlab.com].freeze

  def self.for(source_type)
    klass = FETCHERS[source_type]
    raise ArgumentError, "Unknown source type: #{source_type}" unless klass
    klass.constantize.new
  end

  # Auto-detect source_type from a URL string.
  # Returns one of: "github", "gitlab", "llms_txt", "openapi", "website"
  def self.detect_source_type(url)
    uri = URI.parse(url.strip)
    host = uri.host&.downcase || ""
    path = uri.path&.downcase || ""

    return "github" if GITHUB_HOSTS.include?(host)
    return "gitlab" if GITLAB_HOSTS.include?(host) || gitlab_host?(host)
    return "llms_txt" if path.match?(/llms(?:-full|-small)?\.txt\z/)
    return "openapi" if openapi_path?(path)

    "website"
  rescue URI::InvalidURIError
    "website"
  end

  def self.gitlab_host?(host)
    # Self-hosted GitLab instances often have "gitlab" in the hostname
    host.include?("gitlab")
  end
  private_class_method :gitlab_host?

  def self.openapi_path?(path)
    path.match?(/(?:openapi|swagger).*\.(?:json|ya?ml)\z/) ||
      path.match?(/\/(?:openapi|swagger)\z/) ||
      path.match?(/\/api-docs\z/)
  end
  private_class_method :openapi_path?
end
