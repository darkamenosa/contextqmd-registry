# frozen_string_literal: true

module Analytics::GoalSuggestions
  RESERVED_EVENT_NAMES = %w[pageview engagement].freeze
  LOOKBACK = 6.months

  class << self
    def suggested_event_names(site: ::Analytics::Current.site, exclude: [], limit: 25)
      return [] if site.blank?

      excluded = (Array(exclude).map(&:to_s) + RESERVED_EVENT_NAMES).uniq

      Ahoy::Event
        .for_analytics_site(site)
        .where("ahoy_events.time >= ?", LOOKBACK.ago)
        .where.not(name: [ nil, "" ])
        .where.not(name: excluded)
        .group("ahoy_events.name")
        .order(Arel.sql("COUNT(DISTINCT ahoy_events.visit_id) DESC"), Arel.sql("ahoy_events.name ASC"))
        .limit(limit)
        .pluck(
          Arel.sql("ahoy_events.name"),
          Arel.sql("COUNT(DISTINCT ahoy_events.visit_id)")
        )
        .map do |(name, recent_visits)|
          {
            name: name.to_s,
            recent_visits: recent_visits.to_i
          }
        end
    end
  end
end
