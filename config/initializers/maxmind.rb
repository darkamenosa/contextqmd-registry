# frozen_string_literal: true

require "ipaddr"
require "maxminddb"

DEFAULT_MAXMIND_DB_PATH = Rails.root.join("db/geo/GeoLite2-City.mmdb")

module MaxmindGeo
  extend self

  def reader
    path = database_path
    return nil unless path

    if defined?(@reader) && @reader && @reader_path == path
      return @reader
    end

    @reader&.close if defined?(@reader) && @reader.respond_to?(:close)
    @reader = MaxMindDB.new(path.to_s)
    @reader_path = path
    @reader
  rescue StandardError => e
    Rails.logger.warn("[MaxmindGeo] failed to open DB: #{e.class}: #{e.message}")
    @reader = nil
  end

  def database_path
    env_path = ENV["MAXMIND_DB_PATH"].to_s.presence
    return Pathname.new(env_path) if env_path
    return DEFAULT_MAXMIND_DB_PATH if DEFAULT_MAXMIND_DB_PATH.exist?

    nil
  end

  def available?
    database_path.present?
  end

  def lookup(ip)
    return nil unless valid_ip?(ip)

    result = reader&.lookup(ip.to_s)
    return nil unless result&.found?

    {
      country_iso: result.country&.iso_code,
      city: result.city&.name,
      subdivisions: Array(result.subdivisions).map { |entry| entry.name || entry.iso_code }.compact,
      latitude: result.location&.latitude,
      longitude: result.location&.longitude
    }
  rescue StandardError => e
    Rails.logger.debug("[MaxmindGeo] lookup failed for #{ip.inspect}: #{e.class}: #{e.message}")
    nil
  end

  def valid_ip?(ip)
    addr = IPAddr.new(ip.to_s)
    return false if addr.loopback?
    return false if addr.private?
    return false if addr.link_local?
    return false if addr.ipv6? && addr.to_s == "::"
    return false if addr.ipv4? && addr.to_s == "0.0.0.0"

    true
  rescue StandardError
    false
  end
end
