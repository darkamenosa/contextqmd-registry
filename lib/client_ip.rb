# frozen_string_literal: true

require "ipaddr"
require Rails.root.join("lib/trusted_proxy_ranges")

module ClientIp
  extend self

  def best_effort(request, fallback_ip: nil)
    candidate_ips(request, fallback_ip: fallback_ip).find { |ip| valid_ip?(ip) }
  end

  def public(request, fallback_ip: nil)
    candidate_ips(request, fallback_ip: fallback_ip).find { |ip| public_ip?(ip) }
  end

  def country_hint(request)
    request&.get_header("HTTP_CF_IPCOUNTRY").to_s.upcase.presence
  rescue StandardError
    nil
  end

  private
    def candidate_ips(request, fallback_ip:)
      candidates = []

      if trusted_proxy_source?(request)
        %w[HTTP_CF_CONNECTING_IP HTTP_TRUE_CLIENT_IP].each do |header|
          value = request.get_header(header).to_s.presence
          candidates << value if value
        end

        xff = request.get_header("HTTP_X_FORWARDED_FOR").to_s
        candidates.concat(xff.split(",").map(&:strip)) if xff.present?
      end

      remote_ip = request&.remote_ip.to_s.presence
      candidates << remote_ip if remote_ip

      request_ip = request&.ip.to_s.presence
      candidates << request_ip if request_ip

      remote_addr = request&.get_header("REMOTE_ADDR").to_s.presence
      candidates << remote_addr if remote_addr

      fallback = fallback_ip.to_s.presence
      candidates << fallback if fallback

      candidates.compact.uniq
    rescue StandardError
      fallback = fallback_ip.to_s.presence
      fallback ? [ fallback ] : []
    end

    def trusted_proxy_source?(request)
      return false unless request

      remote_addr = request.get_header("REMOTE_ADDR").to_s
      TrustedProxyRanges.trusted?(remote_addr)
    rescue StandardError
      false
    end

    def valid_ip?(ip)
      parse_ip(ip).present?
    end

    def public_ip?(ip)
      addr = parse_ip(ip)
      return false unless addr
      return false if addr.loopback?
      return false if addr.private?
      return false if addr.link_local?
      return false if addr.ipv6? && addr.to_s == "::"
      return false if addr.ipv4? && addr.to_s == "0.0.0.0"

      true
    end

    def parse_ip(ip)
      IPAddr.new(ip.to_s)
    rescue IPAddr::InvalidAddressError, IPAddr::AddressFamilyError
      nil
    end
end
