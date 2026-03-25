# frozen_string_literal: true

require "cgi"
require "net/http"

module Analytics
  class SourceFavicon
    PLACEHOLDER_PATH = Rails.root.join("public/images/icon/source-fallback.svg")
    PLACEHOLDER_SVG = File.read(PLACEHOLDER_PATH)

    DDG_BROKEN_ICON = "\x89PNG\r\n\x1A\n".b
    FORWARDED_HEADERS = %w[content-type cache-control expires].freeze

    def self.domain_for(source)
      value = CGI.unescape(source.to_s).strip
      return nil if value.blank?

      label = Analytics::SourceResolver.canonical_label(value) || value
      domain = Analytics::SourceResolver.favicon_domain_for(label)
      return domain if domain.present? && label != Analytics::SourceResolver::DIRECT_LABEL

      parse_domain(value)
    end

    def self.fetch(source)
      domain = domain_for(source)
      return nil if domain.blank?

      uri = URI("https://icons.duckduckgo.com/ip3/#{CGI.escape(domain)}.ico")
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
        http.get(uri.request_uri)
      end

      return nil unless response.is_a?(Net::HTTPSuccess)

      body = response.body.to_s.b
      return nil if body == DDG_BROKEN_ICON

      {
        body: body,
        headers: response.to_hash.slice(*FORWARDED_HEADERS)
      }
    rescue StandardError
      nil
    end

    def self.placeholder_svg
      PLACEHOLDER_SVG
    end

    def self.parse_domain(value)
      url = value
      url = "https:#{url}" if url.start_with?("//")
      url = "https://#{url}" if !url.match?(/\Ahttps?:/i) && url.include?(".")
      URI.parse(url).host.presence || fallback_domain(value)
    rescue URI::InvalidURIError
      fallback_domain(value)
    end

    def self.fallback_domain(value)
      host = value.split("/", 2).first.to_s
      host if host.match?(/\A[a-z0-9.-]+\.[a-z]{2,}\z/i)
    end

    private_class_method :parse_domain, :fallback_domain
  end
end
