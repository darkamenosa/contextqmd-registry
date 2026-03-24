# frozen_string_literal: true

require "date"
require "net/http"
require "pathname"

ROOT = Pathname(__dir__).join("../..").expand_path
TARGET = ROOT.join("config/cloudflare_trusted_proxies.txt")
SOURCES = {
  "https://www.cloudflare.com/ips-v4" => "ipv4",
  "https://www.cloudflare.com/ips-v6" => "ipv6"
}.freeze

def fetch_lines(url)
  uri = URI(url)
  response = Net::HTTP.get_response(uri)
  unless response.is_a?(Net::HTTPSuccess)
    raise "failed to fetch #{url}: #{response.code} #{response.message}"
  end

  response.body.each_line.map(&:strip).reject(&:empty?)
end

entries = SOURCES.flat_map do |url, _family|
  fetch_lines(url)
end

content = <<~TEXT
  # Cloudflare published proxy CIDRs.
  # Source:
  # - https://www.cloudflare.com/ips-v4
  # - https://www.cloudflare.com/ips-v6
  # Refreshed: #{Date.today}
  #{entries.join("\n")}
TEXT

TARGET.write(content)
puts "Wrote #{entries.size} proxy CIDRs to #{TARGET}"
