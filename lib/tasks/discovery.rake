# frozen_string_literal: true

require "net/http"
require "json"

module ContextqmdDiscovery
  DEVDOCS_URL = "https://devdocs.io/docs.json"
  GITHUB_API_BASE = "https://api.github.com"
  DEFAULT_MIN_STARS = 5_000
  DEFAULT_OUTPUT_DIR = "tmp/discovery"

  SWEEP_LANGUAGES = %w[
    javascript typescript python ruby go rust java php
    c# swift kotlin c c++ elixir dart scala lua
  ].freeze

  LIBRARY_TOPICS = %w[
    framework library sdk cli tool api orm database
    component ui css web-framework testing
  ].freeze

  SKIP_PATTERNS = [
    /\bawesome[-_]/i,
    /\binterview/i,
    /\bcoding[-_]?challenge/i,
    /\bfree[-_]?programming/i,
    /\btutorial[s]?\b/i,
    /\bcheatsheet/i,
    /\bdotfiles\b/i,
    /\blearn[-_]/i,
    /\b(?:100|30|365)[-_]?days/i,
    /\bcurriculum\b/i,
    /\bresources?\b/i,
    /\bcourse\b/i,
    /system[-_]?design/i
  ].freeze

  # TSV columns: url \t display_name \t stars \t language \t description
  TSV_HEADER = "url\tdisplay_name\tstars\tlanguage\tdescription"

  module_function

  # --- DevDocs source (all unique GitHub repos) ---

  def devdocs(output:, out: $stderr)
    out.puts "Fetching DevDocs catalog..."
    entries = fetch_json(DEVDOCS_URL)
    out.puts "Found #{entries.size} entries in DevDocs"

    repos = extract_github_repos(entries)
    out.puts "Found #{repos.size} unique GitHub repos"

    new_repos = skip_existing(repos, out: out)
    out.puts "#{new_repos.size} new repos (#{repos.size - new_repos.size} already exist)"

    write_tsv(new_repos, output, out: out)
  end

  # --- GitHub popular (single language or topic) ---

  def github_popular(output:, min_stars: DEFAULT_MIN_STARS, language: nil, topic: nil,
                     per_page: 100, pages: 10, out: $stderr)
    all_repos = github_search_query(
      min_stars: min_stars, language: language, topic: topic,
      per_page: per_page, pages: pages, out: out
    )

    all_repos = filter_noise(all_repos, out: out)
    new_repos = skip_existing(all_repos, out: out)
    out.puts "#{new_repos.size} new repos (#{all_repos.size - new_repos.size} already exist)"

    write_tsv(new_repos, output, out: out)
  end

  # --- GitHub sweep across languages ---

  def github_sweep(output:, min_stars: DEFAULT_MIN_STARS, languages: SWEEP_LANGUAGES,
                   per_page: 100, pages_per_lang: 5, out: $stderr)
    seen = Set.new
    all_repos = []

    languages.each_with_index do |lang, lang_idx|
      out.puts "\n[#{lang_idx + 1}/#{languages.size}] Sweeping: #{lang}"
      repos = github_search_query(
        min_stars: min_stars, language: lang,
        per_page: per_page, pages: pages_per_lang, out: out
      )

      added = 0
      repos.each do |repo|
        slug = repo[:github_name].to_s.downcase
        next if seen.include?(slug)

        seen.add(slug)
        all_repos << repo.merge(language: lang)
        added += 1
      end
      out.puts "  +#{added} unique (#{repos.size - added} dupes)"
    end

    out.puts "\nSweep done: #{all_repos.size} unique repos across #{languages.size} languages"

    all_repos = filter_noise(all_repos, out: out)
    new_repos = skip_existing(all_repos, out: out)
    out.puts "#{new_repos.size} new repos (#{all_repos.size - new_repos.size} already exist)"

    write_tsv(new_repos, output, out: out)
  end

  # --- GitHub topic search ---

  def github_topics(output:, min_stars: DEFAULT_MIN_STARS, topics: LIBRARY_TOPICS,
                    per_page: 100, pages_per_topic: 3, out: $stderr)
    seen = Set.new
    all_repos = []

    topics.each_with_index do |topic, idx|
      out.puts "\n[#{idx + 1}/#{topics.size}] Topic: #{topic}"
      repos = github_search_query(
        min_stars: min_stars, topic: topic,
        per_page: per_page, pages: pages_per_topic, out: out
      )

      added = 0
      repos.each do |repo|
        slug = repo[:github_name].to_s.downcase
        next if seen.include?(slug)

        seen.add(slug)
        all_repos << repo.merge(topic_query: topic)
        added += 1
      end
      out.puts "  +#{added} unique (#{repos.size - added} dupes)"
    end

    out.puts "\nTopics done: #{all_repos.size} unique repos across #{topics.size} topics"

    all_repos = filter_noise(all_repos, out: out)
    new_repos = skip_existing(all_repos, out: out)
    out.puts "#{new_repos.size} new repos (#{all_repos.size - new_repos.size} already exist)"

    write_tsv(new_repos, output, out: out)
  end

  # --- Submit URLs to crawl pipeline ---
  #
  # Local mode (kamal exec / rails console):
  #   INPUT=file.tsv or URLS=url1,url2
  #   Uses system account. No identity/login needed.
  #
  # API mode (remote CLI):
  #   INPUT=file.tsv API_URL=https://contextqmd.com API_TOKEN=your_write_token
  #   POSTs to /api/v1/crawl/batches with up to 100 URLs per request.

  def submit(input: nil, urls: nil, api_url: nil, api_token: nil, out: $stderr)
    entries = if input.present?
      load_tsv(input, out: out)
    elsif urls.present?
      urls.split(",").filter_map do |url|
        url = url.strip
        next if url.blank?
        { url: url }
      end
    else
      out.puts "Provide INPUT=file.tsv or URLS=url1,url2,..."
      return
    end

    if api_url.present? && api_token.present?
      submit_via_api(entries, api_url: api_url, api_token: api_token, out: out)
    else
      submit_local(entries, out: out)
    end
  end

  def submit_local(entries, out:)
    out.puts "Submitting #{entries.size} URLs locally..."

    creator = system_user!
    created = 0
    skipped = 0

    entries.each do |entry|
      crawl_request = creator.crawl_requests.create!(
        url: entry[:url],
        metadata: {
          "discovery_source" => entry[:source] || "discovery_import",
          "github_stars" => entry[:stars]&.positive? ? entry[:stars] : nil,
          "language" => entry[:language]
        }.compact
      )
      created += 1
      out.puts "  Queued ##{crawl_request.id}: #{entry[:url]}"
    rescue ActiveRecord::RecordInvalid => e
      skipped += 1
      out.puts "  Skipped #{entry[:url]}: #{e.message}"
    end

    out.puts "\nDone: #{created} created, #{skipped} skipped"
  end

  def submit_via_api(entries, api_url:, api_token:, batch_size: 100, out:)
    endpoint = URI("#{api_url.chomp('/')}/api/v1/crawl/batches")

    unless endpoint.scheme == "https"
      out.puts "ERROR: API_URL must use HTTPS to protect your token. Got: #{endpoint.scheme}"
      return
    end

    out.puts "Submitting #{entries.size} URLs to #{api_url} via API..."
    all_urls = entries.map { |e| e[:url] }
    total_queued = 0
    total_failed = 0

    all_urls.each_slice(batch_size).with_index(1) do |batch, batch_num|
      out.puts "  Batch #{batch_num}: #{batch.size} URLs..."

      body = JSON.generate(urls: batch)
      response = Net::HTTP.start(endpoint.host, endpoint.port, use_ssl: endpoint.scheme == "https",
                                  open_timeout: 10, read_timeout: 60) do |http|
        req = Net::HTTP::Post.new(endpoint.request_uri)
        req["Authorization"] = "Token #{api_token}"
        req["Content-Type"] = "application/json"
        req["Accept"] = "application/json"
        req.body = body
        http.request(req)
      end

      if response.code == "202"
        data = JSON.parse(response.body)
        meta = data["meta"] || {}
        total_queued += meta["queued"].to_i
        total_failed += meta["failed"].to_i
        out.puts "    Queued: #{meta['queued']}, Failed: #{meta['failed']}"
      elsif response.code == "429"
        retry_after = parse_retry_after(response["Retry-After"])
        out.puts "    Rate limited. Waiting #{retry_after}s..."
        sleep(retry_after)
        redo
      else
        out.puts "    API error #{response.code}: #{response.body.to_s.truncate(200)}"
        total_failed += batch.size
      end

      sleep(4)
    end

    out.puts "\nDone: #{total_queued} queued, #{total_failed} failed"
  end

  def load_tsv(path, out: $stderr)
    unless File.exist?(path)
      out.puts "File not found: #{path}"
      return []
    end

    lines = File.readlines(path, chomp: true)
    header = lines.shift
    # Skip header if present, otherwise treat first line as data
    lines.unshift(header) unless header&.start_with?("url\t")

    lines.filter_map do |line|
      next if line.blank? || line.start_with?("#")

      parts = line.split("\t")
      url = parts[0].to_s.strip
      next if url.blank?

      { url: url, stars: parts[2].to_i, language: parts[3].to_s.strip.presence, source: "tsv_import" }
    end.tap { |entries| out.puts "Loaded #{entries.size} entries from #{path}" }
  end

  # --- TSV output ---

  def write_tsv(repos, path, out: $stderr)
    FileUtils.mkdir_p(File.dirname(path))

    File.open(path, "w") do |f|
      f.puts TSV_HEADER
      repos.sort_by { |r| -(r[:stars] || 0) }.each do |r|
        display = r[:devdocs_name] || r[:github_name] || ""
        stars = r[:stars] || 0
        lang = r[:language] || ""
        desc = (r[:description] || "").gsub(/[\t\n\r]/, " ").truncate(200)
        f.puts "#{r[:url]}\t#{display}\t#{stars}\t#{lang}\t#{desc}"
      end
    end

    out.puts "Wrote #{repos.size} entries to #{path}"
  end

  # --- Core GitHub search ---

  def github_search_query(min_stars:, language: nil, topic: nil, per_page: 100, pages: 10, out: $stderr)
    token = github_token
    headers = github_headers(token)
    repos = []

    pages.times do |page_num|
      query = "stars:>=#{min_stars}"
      query += " language:\"#{language}\"" if language.present?
      query += " topic:#{topic}" if topic.present?

      uri = URI("#{GITHUB_API_BASE}/search/repositories?q=#{URI.encode_www_form_component(query)}&sort=stars&order=desc&per_page=#{per_page}&page=#{page_num + 1}")

      response = http_get(uri, headers: headers)

      if response.code == "403" || response.code == "429"
        reset_at = response["x-ratelimit-reset"].to_i
        wait = [ [ reset_at - Time.now.to_i + 1, 1 ].max, 300 ].min
        out.puts "  Rate limited. Waiting #{wait}s..."
        sleep(wait)
        response = http_get(uri, headers: headers)
      end

      unless response.code == "200"
        out.puts "  GitHub API error: #{response.code} — stopping"
        break
      end

      data = JSON.parse(response.body)
      items = data["items"] || []
      total = data["total_count"] || 0
      break if items.empty?

      items.each do |item|
        repos << {
          url: item["html_url"],
          stars: item["stargazers_count"],
          github_name: item["full_name"],
          description: item["description"].to_s.truncate(120),
          homepage: item["homepage"],
          topics: item["topics"] || [],
          language: item["language"]
        }
      end

      remaining = response["x-ratelimit-remaining"].to_i
      out.puts "  Page #{page_num + 1}: #{items.size} repos (total: #{total}, rate limit: #{remaining})"

      break if repos.size >= total

      sleep(token.present? ? 0.5 : 6.0)
    end

    repos
  end

  # --- Helpers ---

  def extract_github_repos(entries)
    seen = Set.new
    repos = []

    entries.each do |entry|
      code_url = entry.dig("links", "code")
      next unless code_url.to_s.include?("github.com")

      normalized = normalize_github_url(code_url)
      next if normalized.nil? || seen.include?(normalized)

      seen.add(normalized)
      repos << {
        url: "https://github.com/#{normalized}",
        devdocs_name: entry["name"],
        devdocs_slug: entry["slug"]
      }
    end

    repos
  end

  def normalize_github_url(url)
    uri = URI.parse(url.to_s.strip)
    return nil unless uri.host&.downcase == "github.com"

    parts = uri.path.to_s.delete_prefix("/").split("/")
    return nil if parts.size < 2

    "#{parts[0]}/#{parts[1]}".sub(/\.git$/, "")
  rescue URI::InvalidURIError
    nil
  end

  def filter_noise(repos, out:)
    before = repos.size
    filtered = repos.reject do |repo|
      name = repo[:github_name].to_s
      SKIP_PATTERNS.any? { |pattern| name.match?(pattern) }
    end
    skipped = before - filtered.size
    out.puts "Filtered #{skipped} non-library repos" if skipped.positive?
    filtered
  end

  def skip_existing(repos, out:)
    existing_source_urls = LibrarySource.pluck(:url).map(&:downcase).to_set
    pending_urls = CrawlRequest.where(status: %w[pending processing]).pluck(:url).map(&:downcase).to_set
    all_known = existing_source_urls | pending_urls

    repos.reject do |repo|
      normalized = LibrarySource.normalize_url(repo[:url], source_type: "github").to_s.downcase
      raw = repo[:url].to_s.downcase
      all_known.include?(normalized) || all_known.include?(raw)
    end
  end

  def system_user!
    Account.system.users.find_by!(role: :system)
  end

  def github_token
    ENV["GITHUB_TOKEN"].to_s.strip.presence
  end

  def github_headers(token = github_token)
    headers = { "Accept" => "application/vnd.github+json", "User-Agent" => "contextqmd-registry" }
    headers["Authorization"] = "Bearer #{token}" if token.present?
    headers
  end

  def fetch_json(url)
    uri = URI(url)
    response = http_get(uri)
    raise "Failed to fetch #{url}: #{response.code}" unless response.code == "200"

    JSON.parse(response.body)
  end

  def http_get(uri, headers: { "User-Agent" => "contextqmd-registry" }, max_redirects: 5)
    max_redirects.times do
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 30) do |http|
        http.get(uri.request_uri, headers)
      end

      if response.is_a?(Net::HTTPRedirection) && response["location"]
        uri = URI(response["location"])
      else
        return response
      end
    end

    raise "Too many redirects for #{uri}"
  end

  # Parse Retry-After header: supports delta-seconds and HTTP-date.
  # Clamps to 5..300 seconds.
  def parse_retry_after(header, default: 60)
    return default if header.blank?

    seconds = header.to_i
    if seconds > 0
      return seconds.clamp(5, 300)
    end

    # Try parsing as HTTP-date
    date = Time.httpdate(header)
    delta = (date - Time.now).ceil
    delta.clamp(5, 300)
  rescue ArgumentError
    default
  end

  def output_path(name)
    dir = ENV["OUTPUT_DIR"] || DEFAULT_OUTPUT_DIR
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    "#{dir}/#{name}_#{timestamp}.tsv"
  end
end

namespace :contextqmd do
  namespace :discover do
    desc "Discover all GitHub repos from DevDocs. OUTPUT=path.tsv"
    task devdocs: :environment do
      output = ENV["OUTPUT"] || ContextqmdDiscovery.output_path("devdocs")
      ContextqmdDiscovery.devdocs(output: output)
    end

    desc "Discover popular GitHub repos. LANGUAGE=ruby TOPIC=framework MIN_STARS=5000 PAGES=10 OUTPUT=path.tsv"
    task github_popular: :environment do
      output = ENV["OUTPUT"] || ContextqmdDiscovery.output_path("github_popular")
      ContextqmdDiscovery.github_popular(
        output: output,
        min_stars: (ENV["MIN_STARS"] || 5000).to_i,
        language: ENV["LANGUAGE"].to_s.strip.presence,
        topic: ENV["TOPIC"].to_s.strip.presence,
        per_page: (ENV["PER_PAGE"] || 100).to_i,
        pages: (ENV["PAGES"] || 10).to_i
      )
    end

    desc "Sweep all languages. MIN_STARS=5000 PAGES_PER_LANG=5 OUTPUT=path.tsv"
    task github_sweep: :environment do
      output = ENV["OUTPUT"] || ContextqmdDiscovery.output_path("github_sweep")
      languages = ENV["LANGUAGES"].to_s.strip.presence&.split(",")&.map(&:strip) || ContextqmdDiscovery::SWEEP_LANGUAGES
      ContextqmdDiscovery.github_sweep(
        output: output,
        min_stars: (ENV["MIN_STARS"] || 5000).to_i,
        languages: languages,
        per_page: (ENV["PER_PAGE"] || 100).to_i,
        pages_per_lang: (ENV["PAGES_PER_LANG"] || 5).to_i
      )
    end

    desc "Discover by library topics. MIN_STARS=5000 PAGES_PER_TOPIC=3 OUTPUT=path.tsv"
    task github_topics: :environment do
      output = ENV["OUTPUT"] || ContextqmdDiscovery.output_path("github_topics")
      topics = ENV["TOPICS"].to_s.strip.presence&.split(",")&.map(&:strip) || ContextqmdDiscovery::LIBRARY_TOPICS
      ContextqmdDiscovery.github_topics(
        output: output,
        min_stars: (ENV["MIN_STARS"] || 5000).to_i,
        topics: topics,
        per_page: (ENV["PER_PAGE"] || 100).to_i,
        pages_per_topic: (ENV["PAGES_PER_TOPIC"] || 3).to_i
      )
    end

    desc "Submit crawl requests. INPUT=file.tsv or URLS=url1,url2. Add API_URL + API_TOKEN for remote."
    task submit: :environment do
      ContextqmdDiscovery.submit(
        input: ENV["INPUT"].to_s.strip.presence,
        urls: ENV["URLS"].to_s.strip.presence,
        api_url: ENV["API_URL"].to_s.strip.presence,
        api_token: ENV["API_TOKEN"].to_s.strip.presence
      )
    end
  end
end
