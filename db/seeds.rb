# frozen_string_literal: true

# Minimal seed data for development.
# To populate libraries with real content, use the crawl pipeline:
#   POST /api/v1/crawl with { url: "https://github.com/rails/rails" }
#
# Usage: bin/rails db:seed

puts "Seeding ContextQMD development data..."

# System account — owns registry-managed libraries and acts as the system actor.
system_account = Account.find_or_create_by!(name: Account::SYSTEM_ACCOUNT_NAME) { |a| a.personal = false }
system_account.users.find_or_create_by!(role: :system) { |u| u.name = "System" }

if Rails.env.development?
  module DevelopmentAnalyticsSeed
    module_function

    PREFIX = "dev-analytics-demo"
    HOSTNAME = "localhost:3000"
    PAGES = [
      "/",
      "/blog",
      "/blog/how-plausible-works",
      "/blog/newsletter",
      "/register",
      "/activate",
      "/pricing",
      "/libraries",
      "/libraries/react",
      "/libraries/rails",
      "/docs/getting-started",
      "/docs/search"
    ].freeze
    DEMO_GOAL_DEFINITIONS = [
      { display_name: "Scroll to Goals", page_path: "/docs/getting-started", scroll_threshold: 60, custom_props: {} },
      { display_name: "Visit /register", page_path: "/register", scroll_threshold: -1, custom_props: {} },
      { display_name: "Add a site", event_name: "Add Site", custom_props: {} },
      { display_name: "Visit /blog*", page_path: "/blog*", scroll_threshold: -1, custom_props: {} },
      { display_name: "Visit /activate", page_path: "/activate", scroll_threshold: -1, custom_props: {} },
      { display_name: "Sign up for a trial", event_name: "Trial Signup", custom_props: {} },
      { display_name: "Sign up via invitation", event_name: "Invitation Signup", custom_props: {} },
      { display_name: "Weekly Email Note Click", event_name: "Weekly Email Note Click", custom_props: {} },
      { display_name: "Sign up to a newsletter", event_name: "Newsletter Signup", custom_props: {} }
    ].freeze
    DEMO_ALLOWED_EVENT_PROPS = %w[browser_language logged_in theme author plan].freeze
    DEMO_FUNNELS = [
      {
        name: "Blog to Email Newsletter",
        steps: [
          { type: "page", match: "contains", value: "/blog", name: "Visit /blog*" },
          { type: "event", match: "equals", value: "Newsletter Signup", name: "Sign up to a newsletter" }
        ]
      },
      {
        name: "Blog to Register",
        steps: [
          { type: "page", match: "contains", value: "/blog", name: "Visit /blog*" },
          { type: "page", match: "equals", value: "/register", name: "Visit /register" }
        ]
      },
      {
        name: "Registration & Onboarding",
        steps: [
          { type: "page", match: "equals", value: "/register", name: "Visit /register" },
          { type: "event", match: "equals", value: "Signup", name: "Signup" },
          { type: "page", match: "equals", value: "/activate", name: "Visit /activate" }
        ]
      }
    ].freeze
    SOURCES = [
      { referrer: nil, referring_domain: nil, utm_source: nil, utm_medium: nil, utm_campaign: nil },
      { referrer: "https://www.google.com/search?q=contextqmd", referring_domain: "google.com", utm_source: "google", utm_medium: "organic", utm_campaign: nil },
      { referrer: "https://news.ycombinator.com/item?id=1", referring_domain: "news.ycombinator.com", utm_source: "hacker-news", utm_medium: "social", utm_campaign: "launch-week" },
      { referrer: "https://github.com/tuyenhx/contextqmd-registry", referring_domain: "github.com", utm_source: "github", utm_medium: "referral", utm_campaign: nil },
      { referrer: "https://x.com/contextqmd/status/1", referring_domain: "x.com", utm_source: "x", utm_medium: "social", utm_campaign: "analytics-check" },
      { referrer: "https://chatgpt.com/c/abc123", referring_domain: "chatgpt.com", utm_source: nil, utm_medium: nil, utm_campaign: nil },
      { referrer: "https://www.perplexity.ai/search/contextqmd", referring_domain: "perplexity.ai", utm_source: nil, utm_medium: nil, utm_campaign: nil },
      { referrer: "https://search.brave.com/search?q=contextqmd", referring_domain: "search.brave.com", utm_source: nil, utm_medium: nil, utm_campaign: nil },
      { referrer: "https://app.slack.com/client/T123/C456", referring_domain: "app.slack.com", utm_source: nil, utm_medium: nil, utm_campaign: nil },
      { referrer: "https://www.producthunt.com/posts/contextqmd", referring_domain: "producthunt.com", utm_source: nil, utm_medium: nil, utm_campaign: "launch-week" },
      { referrer: "https://statics.teams.cdn.office.net/evergreen-assets/safelinks", referring_domain: "statics.teams.cdn.office.net", utm_source: nil, utm_medium: nil, utm_campaign: nil },
      { referrer: "https://en.wikipedia.org/wiki/Documentation", referring_domain: "en.wikipedia.org", utm_source: nil, utm_medium: nil, utm_campaign: nil },
      { referrer: "https://canary.discord.com/channels/1/2", referring_domain: "canary.discord.com", utm_source: nil, utm_medium: nil, utm_campaign: nil },
      { referrer: nil, referring_domain: nil, utm_source: "fb_ad", utm_medium: "cpc", utm_campaign: "spring-launch" },
      { referrer: nil, referring_domain: nil, utm_source: "search-ads", utm_medium: "ppc", utm_campaign: "docs-growth" },
      { referrer: nil, referring_domain: nil, utm_source: "newsletter", utm_medium: "email", utm_campaign: "weekly-roundup" },
      { referrer: nil, referring_domain: nil, utm_source: "producthunt", utm_medium: "social", utm_campaign: "launch-week" }
    ].freeze
    LOCATIONS = [
      { country: "US", region: "California", city: "San Francisco", latitude: 37.7749, longitude: -122.4194 },
      { country: "US", region: "New York", city: "New York", latitude: 40.7128, longitude: -74.0060 },
      { country: "VN", region: "Ho Chi Minh City", city: "Ho Chi Minh City", latitude: 10.7769, longitude: 106.7009 },
      { country: "DE", region: "Berlin", city: "Berlin", latitude: 52.5200, longitude: 13.4050 },
      { country: "JP", region: "Tokyo", city: "Tokyo", latitude: 35.6762, longitude: 139.6503 }
    ].freeze
    DEVICES = [
      { browser: "Chrome", browser_version: "135.0", os: "Mac OS X", device_type: "Desktop", screen_size: "1440x900" },
      { browser: "Safari", browser_version: "17.4", os: "iOS", device_type: "Mobile", screen_size: "390x844" },
      { browser: "Firefox", browser_version: "136.0", os: "Windows", device_type: "Desktop", screen_size: "1920x1080" },
      { browser: "Edge", browser_version: "134.0", os: "Windows", device_type: "Laptop", screen_size: "1536x960" },
      { browser: "DuckDuckGo Privacy Browser", browser_version: "5.219.0", os: "Android", device_type: "Mobile", screen_size: "412x915" },
      { browser: "Ecosia", browser_version: "134.0", os: "Android", device_type: "Mobile", screen_size: "393x852" },
      { browser: "Huawei Browser Mobile", browser_version: "15.0", os: "HarmonyOS", device_type: "Mobile", screen_size: "430x932" },
      { browser: "QQ Browser", browser_version: "16.2", os: "Android", device_type: "Tablet", screen_size: "820x1180" },
      { browser: "MIUI Browser", browser_version: "18.8", os: "Android", device_type: "Mobile", screen_size: "393x873" },
      { browser: "curl", browser_version: "8.8.0", os: "GNU/Linux", device_type: "Desktop", screen_size: "1280x800" },
      { browser: "vivo Browser", browser_version: "23.1", os: "Android", device_type: "Mobile", screen_size: "412x892" },
      { browser: "Samsung Browser", browser_version: "27.0", os: "Tizen", device_type: "TV", screen_size: "1920x1080" },
      { browser: "Chrome", browser_version: "134.0", os: "Fire OS", device_type: "Tablet", screen_size: "1280x800" },
      { browser: "Chrome", browser_version: "135.0", os: "KaiOS", device_type: "Mobile", screen_size: "320x240" },
      { browser: "PlayStation Browser", browser_version: "3.11", os: "PlayStation", device_type: "Console", screen_size: "1920x1080" }
    ].freeze
    AUTHORS = [ "Alice", "Bao", "Mai", "Luca" ].freeze
    THEMES = %w[light dark system].freeze
    LANGUAGES = [ "en-US", "vi-VN", "de-DE", "ja-JP" ].freeze

    def seed!
      cleanup!
      ensure_behavior_config!

      now = Time.zone.now.change(usec: 0)
      today = now.to_date
      current_hour = now.hour

      today_counts = build_today_counts(current_hour)
      yesterday_counts = build_yesterday_counts

      create_hourly_visits!(today - 1.day, yesterday_counts)
      create_hourly_visits!(today, today_counts)
      create_live_visitors!(now)

      puts "Seeded analytics demo data:"
      puts "  Goals: #{Goal.order(:display_name).pluck(:display_name).join(', ')}"
      puts "  Property keys: #{Ahoy::Visit.available_property_keys.join(', ')}"
      puts "  Funnels: #{Funnel.order(:name).pluck(:name).join(', ')}"
      puts "  Seed source labels: #{seed_source_labels.join(', ')}"
      puts "  Seed browsers: #{DEVICES.map { |device| device[:browser] }.uniq.join(', ')}"
      puts "  Seed operating systems: #{DEVICES.map { |device| device[:os] }.uniq.join(', ')}"
      puts "  Today hourly visits: #{today_counts.inspect}"
      puts "  Yesterday hourly visits: #{yesterday_counts.inspect}"
      puts "  Dashboard check: /admin/analytics/reports?period=day&comparison=previous_period"
    end

    def cleanup!
      visits = Ahoy::Visit.where("visit_token LIKE ?", "#{PREFIX}-%")
      visit_ids = visits.pluck(:id)
      Ahoy::Event.where(visit_id: visit_ids).delete_all if visit_ids.any?
      visits.delete_all
    end

    def ensure_behavior_config!
      Goal.sync_from_definitions!(DEMO_GOAL_DEFINITIONS)
      AnalyticsSetting.set_bool("goals_managed", true)
      AnalyticsSetting.set_json(
        "allowed_event_props",
        (Ahoy::Visit.available_property_keys + DEMO_ALLOWED_EVENT_PROPS).uniq.sort
      )

      DEMO_FUNNELS.each do |payload|
        funnel = Funnel.find_or_initialize_by(name: payload.fetch(:name))
        funnel.steps = payload.fetch(:steps)
        funnel.save!
      end
    end

    def build_today_counts(current_hour)
      base = [ 4, 6, 5, 4, 4, 5, 7, 8, 7, 9, 10, 8, 11, 12, 9, 3, 0, 0, 0, 0, 0, 0, 0, 0 ]
      base.each_with_index.map do |count, hour|
        next 0 if hour > current_hour
        next [ count, 2 ].min if hour == current_hour

        count
      end
    end

    def build_yesterday_counts
      [ 3, 5, 4, 4, 5, 5, 6, 6, 8, 8, 9, 9, 10, 10, 8, 7, 6, 5, 5, 4, 4, 3, 3, 2 ]
    end

    def create_hourly_visits!(date, counts)
      counts.each_with_index do |count, hour|
        count.times do |index|
          create_visit_with_events!(
            bucket_time: Time.zone.local(date.year, date.month, date.day, hour, 0, 0),
            sequence: "#{date.iso8601}-#{hour}-#{index}",
            burst_index: index,
            live: false
          )
        end
      end
    end

    def create_live_visitors!(now)
      3.times do |index|
        create_visit_with_events!(
          bucket_time: now - (index + 1).minutes,
          sequence: "live-#{index}",
          burst_index: index,
          live: true
        )
      end
    end

    def create_visit_with_events!(bucket_time:, sequence:, burst_index:, live:)
      source = SOURCES[burst_index % SOURCES.length]
      location = LOCATIONS[burst_index % LOCATIONS.length]
      device = DEVICES[burst_index % DEVICES.length]
      scenario = scenario_for(burst_index, live)
      pages = scenario.fetch(:pages)
      second_offset = ((burst_index * 7) % 50).seconds
      started_at = [ bucket_time + second_offset, Time.zone.now.change(usec: 0) ].min

      visit = Ahoy::Visit.create!(
        visit_token: "#{PREFIX}-visit-#{sequence}",
        visitor_token: "#{PREFIX}-visitor-#{sequence}",
        started_at: started_at,
        ip: "203.0.113.#{(burst_index % 200) + 1}",
        user_agent: "ContextQMD Dev Seed",
        landing_page: pages.first,
        hostname: HOSTNAME,
        browser: device[:browser],
        browser_version: device[:browser_version],
        os: device[:os],
        device_type: device[:device_type],
        screen_size: device[:screen_size],
        country: location[:country],
        region: location[:region],
        city: location[:city],
        latitude: location[:latitude],
        longitude: location[:longitude],
        referrer: source[:referrer],
        referring_domain: source[:referring_domain],
        utm_source: source[:utm_source],
        utm_medium: source[:utm_medium],
        utm_campaign: source[:utm_campaign]
      )

      pages.each_with_index do |page, event_index|
        Ahoy::Event.create!(
          visit: visit,
          name: "pageview",
          time: [ started_at + event_index.minutes + 5.seconds, Time.zone.now.change(usec: 0) ].min,
          properties: {
            page: page,
            title: "Dev analytics sample"
          }
        )
      end

      create_engagement_event!(visit, started_at, scenario) unless live

      scenario.fetch(:events).each_with_index do |event_payload, index|
        Ahoy::Event.create!(
          visit: visit,
          name: event_payload.fetch(:name),
          time: [ started_at + (index + 1).minutes + 20.seconds, Time.zone.now.change(usec: 0) ].min,
          properties: event_payload.fetch(:properties)
        )
      end
    end

    def create_engagement_event!(visit, started_at, scenario)
      engagement_page = scenario[:engagement_page]
      return if engagement_page.blank?

      Ahoy::Event.create!(
        visit: visit,
        name: "engagement",
        time: [ started_at + 45.seconds, Time.zone.now.change(usec: 0) ].min,
        properties: {
          page: engagement_page,
          engaged_ms: 12_000 + ((scenario[:seed] % 4) * 3_000),
          scroll_depth: 70 + ((scenario[:seed] % 3) * 10)
        }
      )
    end

    def scenario_for(burst_index, live)
      return { pages: [ PAGES[burst_index % PAGES.length] ], events: [], seed: burst_index } if live

      props = behavior_props_for(burst_index)

      case burst_index % 6
      when 0
        {
          pages: [ "/blog", "/blog/newsletter" ],
          engagement_page: "/blog/newsletter",
          events: [
            { name: "Newsletter Signup", properties: props.merge(page: "/blog/newsletter") },
            { name: "Weekly Email Note Click", properties: props.merge(page: "/blog/newsletter") }
          ],
          seed: burst_index
        }
      when 1
        {
          pages: [ "/blog/how-plausible-works", "/register", "/activate" ],
          engagement_page: "/blog/how-plausible-works",
          events: [
            { name: "Signup", properties: props.merge(page: "/register") },
            { name: "Invitation Signup", properties: props.merge(page: "/register") }
          ],
          seed: burst_index
        }
      when 2
        {
          pages: [ "/register", "/activate", "/pricing" ],
          events: [
            { name: "Signup", properties: props.merge(page: "/register") },
            { name: "Trial Signup", properties: props.merge(page: "/pricing") },
            { name: "Add Site", properties: props.merge(page: "/activate") }
          ],
          seed: burst_index
        }
      when 3
        {
          pages: [ "/docs/getting-started", "/libraries/react" ],
          engagement_page: "/docs/getting-started",
          events: [
            { name: "Docs CTA Click", properties: props.merge(page: "/docs/getting-started") }
          ],
          seed: burst_index
        }
      when 4
        {
          pages: [ "/", "/blog", "/register" ],
          events: [
            { name: "Signup", properties: props.merge(page: "/register") }
          ],
          seed: burst_index
        }
      else
        {
          pages: [ "/libraries/rails", "/docs/search" ],
          events: [
            { name: "Search", properties: props.merge(page: "/docs/search", query: "analytics") }
          ],
          seed: burst_index
        }
      end
    end

    def behavior_props_for(burst_index)
      {
        browser_language: LANGUAGES[burst_index % LANGUAGES.length],
        logged_in: burst_index.even? ? "true" : "false",
        theme: THEMES[burst_index % THEMES.length],
        author: AUTHORS[burst_index % AUTHORS.length],
        plan: %w[Starter Pro Team][burst_index % 3]
      }
    end

    def seed_source_labels
      SOURCES.map do |source|
        Analytics::SourceResolver.resolve(
          referring_domain: source[:referring_domain],
          utm_source: source[:utm_source]
        ).source_label
      end.uniq
    end
  end

  DevelopmentAnalyticsSeed.seed!
end

puts "Done."
