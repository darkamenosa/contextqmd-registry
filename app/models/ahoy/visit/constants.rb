module Ahoy::Visit::Constants
  extend ActiveSupport::Concern

  UNKNOWN_LABEL = "(unknown)".freeze
  NONE_LABEL = "(none)".freeze
  NOT_SET_LABEL = "(not set)".freeze
  DIRECT_LABEL = "Direct / None".freeze

  EVENT_PAGEVIEW = "pageview".freeze
  EVENT_ENGAGEMENT = "engagement".freeze
end
