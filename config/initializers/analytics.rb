# Analytics configuration bootstrap
Rails.configuration.x.analytics ||= ActiveSupport::OrderedOptions.new

cfg = Rails.configuration.x.analytics

cfg.server_visits = ENV.fetch("ANALYTICS_SERVER_VISITS", "false") == "true"
cfg.use_cookies = false
cfg.use_beacon_for_events = true
cfg.visit_duration_minutes = 240
