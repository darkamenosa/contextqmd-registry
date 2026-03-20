# frozen_string_literal: true

require "ipaddr"
require "resolv"

# Shared SSRF protection for redirect targets.
# Used by CrawlRequest (initial validation) and fetchers (redirect revalidation).
#
# Fail-closed: anything we can't resolve or parse is blocked.
class SsrfGuard
  PRIVATE_RANGES = [
    # IPv4
    IPAddr.new("127.0.0.0/8"),       # loopback
    IPAddr.new("10.0.0.0/8"),        # RFC1918
    IPAddr.new("172.16.0.0/12"),     # RFC1918
    IPAddr.new("192.168.0.0/16"),    # RFC1918
    IPAddr.new("169.254.0.0/16"),    # link-local
    IPAddr.new("0.0.0.0/8"),         # "this" network
    # IPv6
    IPAddr.new("::1/128"),           # loopback
    IPAddr.new("fc00::/7"),          # unique local
    IPAddr.new("fe80::/10"),         # link-local
    IPAddr.new("::/128"),            # unspecified
    IPAddr.new("::ffff:127.0.0.0/104"),  # IPv4-mapped loopback
    IPAddr.new("::ffff:10.0.0.0/104"),   # IPv4-mapped RFC1918
    IPAddr.new("::ffff:172.16.0.0/108"), # IPv4-mapped RFC1918
    IPAddr.new("::ffff:192.168.0.0/112"), # IPv4-mapped RFC1918
    IPAddr.new("::ffff:169.254.0.0/112"), # IPv4-mapped link-local
    IPAddr.new("::ffff:0.0.0.0/104")     # IPv4-mapped "this" network
  ].freeze

  # Numeric/abbreviated IP forms that bypass DNS but resolve to private addresses.
  # Covers decimal (2130706433), hex (0x7f000001), and shorthand (127.1).
  SUSPICIOUS_HOST_PATTERN = /\A(
    localhost |
    0\.0\.0\.0 |
    127\.\d+\.\d+\.\d+ |
    127\.\d+ |
    \[::1\] |
    \[::ffff:127\. |
    0x[0-9a-f]+ |
    \d{8,10}
  )\z/ix

  def self.safe_uri?(uri)
    host = uri.host
    return false if host.blank?
    return false if host.match?(SUSPICIOUS_HOST_PATTERN)

    # Try to parse host as a literal IP (catches numeric forms like 2130706433)
    return false if literal_private_ip?(host)

    addrs = Resolv.getaddresses(host)
    # Fail closed: no addresses = blocked. Proxy could resolve differently.
    return false if addrs.empty?

    addrs.none? { |addr| private_ip?(addr) }
  rescue Resolv::ResolvError
    false
  end

  def self.private_ip?(addr_string)
    ip = IPAddr.new(addr_string)
    PRIVATE_RANGES.any? { |range| range.include?(ip) }
  rescue IPAddr::InvalidAddressError
    true
  end

  # Check if host is a literal IP address (including numeric/hex forms).
  # Ruby's IPAddr.new can parse decimal and hex integer IPs.
  def self.literal_private_ip?(host)
    # Strip brackets from IPv6 literals
    cleaned = host.delete_prefix("[").delete_suffix("]")
    ip = IPAddr.new(cleaned)
    PRIVATE_RANGES.any? { |range| range.include?(ip) }
  rescue IPAddr::InvalidAddressError, IPAddr::AddressFamilyError
    false # Not a literal IP — will go through DNS
  end
end
