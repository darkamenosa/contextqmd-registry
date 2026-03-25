# Analytics configuration bootstrap
Rails.configuration.x.analytics ||= ActiveSupport::OrderedOptions.new

cfg = Rails.configuration.x.analytics

cfg.server_visits = true
cfg.use_cookies = false
cfg.use_beacon_for_events = false
cfg.visit_duration_minutes = 30
