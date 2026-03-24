# frozen_string_literal: true

require "ipaddr"

module TrustedProxyRanges
  extend self

  CLOUDFLARE_FILE = Rails.root.join("config/cloudflare_trusted_proxies.txt")
  EXTRA_PROXY_ENV_KEYS = %w[TRUSTED_PROXY_CIDRS CLOUDFLARE_TRUSTED_PROXY_CIDRS].freeze

  def all
    @all ||= begin
      proxies = ActionDispatch::RemoteIp::TRUSTED_PROXIES.dup
      proxies.concat(load_file(CLOUDFLARE_FILE))
      EXTRA_PROXY_ENV_KEYS.each do |key|
        proxies.concat(parse_list(ENV[key]))
      end
      proxies.uniq(&:to_s)
    end
  end

  def trusted?(ip)
    address = parse_ip(ip)
    return false unless address

    all.any? { |proxy| proxy.include?(address) }
  end

  private
    def load_file(path)
      return [] unless path.exist?

      parse_list(path.read)
    end

    def parse_list(raw)
      raw.to_s.each_line.filter_map do |line|
        value = line.sub(/#.*/, "").strip
        next if value.empty?

        IPAddr.new(value)
      rescue IPAddr::InvalidAddressError
        Rails.logger.warn("[TrustedProxyRanges] ignoring invalid CIDR #{value.inspect}")
        nil
      end
    end

    def parse_ip(ip)
      IPAddr.new(ip.to_s)
    rescue IPAddr::InvalidAddressError, IPAddr::AddressFamilyError
      nil
    end
end
