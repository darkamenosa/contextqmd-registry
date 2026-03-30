# Analytics host configuration.
#
# Analytics owns its own public setup surface. Most defaults already live in
# `Analytics::Config`, so only override what this host app actually needs.
require Rails.root.join("lib/analytics")

Analytics.setup do |config|
  # Optional runtime overrides:
  # config.mode = :single_site           # default
  # config.server_visits = true          # default
  # config.use_cookies = false           # default
  # config.use_beacon_for_events = false # default
  # config.visit_duration_minutes = 30   # default
  # config.public_base_url = "https://analytics.example.com"

  # Optional single-site bootstrap hints:
  # config.default_site.host = "localhost"
  # config.default_site.name = "contextqmd.com"

  # Provider credentials:
  # config.google_search_console.client_id = ENV["GOOGLE_SEARCH_CONSOLE_CLIENT_ID"]
  # config.google_search_console.client_secret = ENV["GOOGLE_SEARCH_CONSOLE_CLIENT_SECRET"]
  # config.google_search_console.callback_path = "/admin/settings/analytics/google_search_console/callback" # default
end
