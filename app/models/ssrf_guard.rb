# frozen_string_literal: true

require "ipaddr"
require "resolv"

# Shared SSRF protection for redirect targets.
# Used by CrawlRequest (initial validation) and fetchers (redirect revalidation).
class SsrfGuard
  PRIVATE_RANGES = [
    IPAddr.new("127.0.0.0/8"),
    IPAddr.new("10.0.0.0/8"),
    IPAddr.new("172.16.0.0/12"),
    IPAddr.new("192.168.0.0/16"),
    IPAddr.new("169.254.0.0/16"),
    IPAddr.new("::1/128"),
    IPAddr.new("fc00::/7")
  ].freeze

  # Returns true if the URI host resolves to a public (non-private) address.
  def self.safe_uri?(uri)
    host = uri.host
    return false if host.blank?
    return false if host.match?(/\A(localhost|0\.0\.0\.0|127\.\d+\.\d+\.\d+)\z/i)

    addrs = Resolv.getaddresses(host)
    addrs.none? { |addr| PRIVATE_RANGES.any? { |range| range.include?(IPAddr.new(addr)) rescue false } }
  rescue Resolv::ResolvError
    true # can't resolve — allow (will fail at connect time)
  end
end
