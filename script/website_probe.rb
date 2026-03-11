#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "json"
require "optparse"
require "securerandom"
require "timeout"
require_relative "../config/environment"

options = {
  runner: "auto",
  preview: 300,
  full_content: false,
  no_proxy: false,
  proxy_id: nil,
  timeout: 60,
  max_pages: nil
}

OptionParser.new do |parser|
  parser.banner = "Usage: ruby script/website_probe.rb <url> [--runner auto|ruby|node] [--max-pages 1] [--preview 300] [--proxy-id 4]"

  parser.on("--runner RUNNER", %w[auto ruby node], "Crawler runner to use") do |runner|
    options[:runner] = runner
  end

  parser.on("--preview N", Integer, "Number of content characters to print in preview") do |preview|
    options[:preview] = preview
  end

  parser.on("--full-content", "Print the full first page content instead of truncating it") do
    options[:full_content] = true
  end

  parser.on("--no-proxy", "Disable proxy lookup for this probe run only") do
    options[:no_proxy] = true
  end

  parser.on("--proxy-id ID", Integer, "Force a specific CrawlProxyConfig id for this probe run") do |proxy_id|
    options[:proxy_id] = proxy_id
  end

  parser.on("--timeout SECONDS", Integer, "Abort the probe after this many seconds") do |seconds|
    options[:timeout] = seconds
  end

  parser.on("--max-pages N", Integer, "Maximum pages to crawl. Use 1 for a single-page probe") do |count|
    options[:max_pages] = count if count.positive?
  end
end.parse!

url = ARGV.shift
if url.blank?
  warn "Missing URL"
  warn "Example: mise exec -- ruby script/website_probe.rb https://developers.cloudflare.com/browser-rendering/ --runner auto"
  exit 1
end

request = Struct.new(:url, :metadata, :library_id, :library, :id)
  .new(
    url,
    {
      "website_runner" => options[:runner],
      "website_max_pages" => options[:max_pages]
    }.compact,
    nil,
    nil,
    "probe-#{options[:runner]}-#{Process.pid}-#{SecureRandom.hex(6)}"
  )

fetcher = DocsFetcher::Website.new

def proxy_payload(proxy)
  return nil unless proxy

  {
    id: proxy.id,
    name: proxy.name,
    scheme: proxy.scheme,
    host: proxy.host,
    port: proxy.port,
    provider: proxy.provider,
    kind: proxy.kind,
    usage_scope: proxy.usage_scope
  }
end

begin
  original_checkout = ProxyPool.method(:checkout)
  original_next_proxy_config = ProxyPool.method(:next_proxy_config)
  selected_proxy = nil

  if options[:no_proxy]
    ProxyPool.define_singleton_method(:checkout) { |**_options| nil }
    ProxyPool.define_singleton_method(:next_proxy_config) { |**_options| nil }
  elsif options[:proxy_id]
    forced_proxy = CrawlProxyConfig.find(options[:proxy_id])

    ProxyPool.define_singleton_method(:checkout) do |scope:, target_host: nil, session_key:, sticky_session: false|
      selected_proxy = forced_proxy
      forced_proxy.crawl_proxy_leases.create!(
        usage_scope: scope,
        session_key: session_key,
        target_host: target_host,
        sticky_session: sticky_session,
        last_seen_at: Time.current,
        expires_at: Time.current + forced_proxy.lease_ttl,
        metadata: { "probe" => true }
      )
    end

    ProxyPool.define_singleton_method(:next_proxy_config) do |**_options|
      selected_proxy = forced_proxy
      forced_proxy
    end
  else
    ProxyPool.define_singleton_method(:checkout) do |**checkout_options|
      lease = original_checkout.call(**checkout_options)
      selected_proxy = lease&.crawl_proxy_config
      lease
    end

    ProxyPool.define_singleton_method(:next_proxy_config) do |**proxy_options|
      proxy = original_next_proxy_config.call(**proxy_options)
      selected_proxy = proxy
      proxy
    end
  end

  result = Timeout.timeout(options[:timeout]) do
    fetcher.fetch(
      request,
      on_progress: lambda do |message, **progress|
        puts({ type: "progress", message: message, progress: progress }.to_json)
      end
    )
  end

  first_page = result.pages.first || {}
  first_content = first_page[:content].to_s
  puts(
    {
      type: "result",
      runner: options[:runner],
      no_proxy: options[:no_proxy],
      proxy: proxy_payload(selected_proxy),
      pages: result.pages.size,
      first_title: first_page[:title],
      first_url: first_page[:url],
      first_preview: options[:full_content] ? first_content : first_content.slice(0, options[:preview])
    }.to_json
  )
rescue StandardError => error
  warn(
    {
      type: "error",
      runner: options[:runner],
      no_proxy: options[:no_proxy],
      proxy: proxy_payload(selected_proxy),
      error_class: error.class.name,
      message: error.message
    }.to_json
  )
  exit 1
ensure
  ProxyPool.define_singleton_method(:checkout, original_checkout) if defined?(original_checkout) && original_checkout
  ProxyPool.define_singleton_method(:next_proxy_config, original_next_proxy_config) if defined?(original_next_proxy_config) && original_next_proxy_config
end
