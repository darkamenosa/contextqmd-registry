# frozen_string_literal: true

namespace :analytics do
  namespace :profiles do
    desc "Rebuild analytics profile projections (optionally PROFILE_ID=... or SITE_ID=...)"
    task rebuild: :environment do
      scope = AnalyticsProfile.canonical.order(:id)
      scope = scope.where(id: ENV["PROFILE_ID"]) if ENV["PROFILE_ID"].present?
      scope = scope.where(analytics_site_id: ENV["SITE_ID"]) if ENV["SITE_ID"].present?

      total = scope.count
      if total.zero?
        puts "No canonical analytics profiles matched."
        next
      end

      puts "Rebuilding #{total} analytics profile projection#{'s' unless total == 1}..."

      scope.find_each.with_index(1) do |profile, index|
        profile.rebuild_projection_now
        puts "  [#{index}/#{total}] rebuilt profile #{profile.id} (#{profile.public_id})"
      end

      puts "Profile rebuild complete."
    end

    desc "Refresh analytics profile summaries only (optionally PROFILE_ID=... or SITE_ID=...)"
    task refresh_summaries: :environment do
      scope = AnalyticsProfile.canonical.order(:id)
      scope = scope.where(id: ENV["PROFILE_ID"]) if ENV["PROFILE_ID"].present?
      scope = scope.where(analytics_site_id: ENV["SITE_ID"]) if ENV["SITE_ID"].present?

      total = scope.count
      if total.zero?
        puts "No canonical analytics profiles matched."
        next
      end

      puts "Refreshing #{total} analytics profile summary#{'ies' unless total == 1}..."

      scope.find_each.with_index(1) do |profile, index|
        profile.rebuild_summary_now
        puts "  [#{index}/#{total}] refreshed summary for profile #{profile.id} (#{profile.public_id})"
      end

      puts "Profile summary refresh complete."
    end
  end

  namespace :visits do
    desc "Replay visit projection from raw facts (optionally VISIT_ID=... or SITE_ID=...)"
    task replay: :environment do
      scope = Analytics::FactStore.visit_relation(site: nil, order: :asc)
      scope = scope.where(id: ENV["VISIT_ID"]) if ENV["VISIT_ID"].present?
      scope = scope.where(analytics_site_id: ENV["SITE_ID"]) if ENV["SITE_ID"].present?

      total = scope.count
      if total.zero?
        puts "No visits matched."
        next
      end

      puts "Replaying #{total} visit projection#{'s' unless total == 1}..."

      scope.find_each.with_index(1) do |visit, index|
        visit.project_now
        puts "  [#{index}/#{total}] replayed visit #{visit.id}"
      end

      puts "Visit replay complete."
    end

    desc "Refresh canonical visit summaries from raw facts (optionally VISIT_ID=... or SITE_ID=...)"
    task refresh_summaries: :environment do
      scope = Analytics::FactStore.visit_relation(site: nil, order: :asc)
      scope = scope.where(id: ENV["VISIT_ID"]) if ENV["VISIT_ID"].present?
      scope = scope.where(analytics_site_id: ENV["SITE_ID"]) if ENV["SITE_ID"].present?

      total = scope.count
      if total.zero?
        puts "No visits matched."
        next
      end

      puts "Refreshing visit summaries for #{total} visit#{'s' unless total == 1}..."

      scope.find_each.with_index(1) do |visit, index|
        Analytics::VisitSummary.refresh_visit!(visit)
        puts "  [#{index}/#{total}] refreshed visit summary for visit #{visit.id}"
      end

      puts "Visit summary refresh complete."
    end

    desc "Refresh visit page summaries from raw pageviews (legacy alias for refresh_summaries)"
    task refresh_page_summaries: :refresh_summaries

    desc "Refresh visit page engagements from raw pageviews and engagement events (optionally VISIT_ID=... or SITE_ID=...)"
    task refresh_page_engagements: :environment do
      scope = Analytics::FactStore.visit_relation(site: nil, order: :asc)
      scope = scope.where(id: ENV["VISIT_ID"]) if ENV["VISIT_ID"].present?
      scope = scope.where(analytics_site_id: ENV["SITE_ID"]) if ENV["SITE_ID"].present?

      total = scope.count
      if total.zero?
        puts "No visits matched."
        next
      end

      puts "Refreshing visit page engagements for #{total} visit#{'s' unless total == 1}..."

      scope.find_each.with_index(1) do |visit, index|
        Analytics::VisitPageEngagement.refresh_visit!(visit)
        puts "  [#{index}/#{total}] refreshed visit page engagement for visit #{visit.id}"
      end

      puts "Visit page engagement refresh complete."
    end
  end

  namespace :rollups do
    desc "Refresh site visit hourly rollups (optionally SITE_ID=..., FROM=..., TO=...)"
    task refresh_visits: :environment do
      refresh_hourly_rollups!(
        label: "visit",
        earliest_at: ->(site_id) { Analytics::FactStore.visit_relation(site: site_id).minimum(:started_at) },
        refresh_range: ->(site_id, range) { Analytics::SiteVisitHourlyRollup.refresh_range!(site: site_id, range:) }
      )
    end

    desc "Refresh site event hourly rollups (optionally SITE_ID=..., FROM=..., TO=...)"
    task refresh_events: :environment do
      refresh_hourly_rollups!(
        label: "event",
        earliest_at: ->(site_id) { Analytics::FactStore.event_relation(site: site_id).minimum(:time) },
        refresh_range: ->(site_id, range) { Analytics::SiteEventHourlyRollup.refresh_range!(site: site_id, range:) }
      )
    end

    desc "Refresh site source hourly visitor rollups (optionally SITE_ID=..., FROM=..., TO=...)"
    task refresh_sources: :environment do
      refresh_hourly_rollups!(
        label: "source visitor",
        earliest_at: ->(site_id) { Analytics::FactStore.visit_relation(site: site_id).minimum(:started_at) },
        refresh_range: ->(site_id, range) { Analytics::SiteSourceHourlyVisitorRollup.refresh_range!(site: site_id, range:) }
      )
    end

    desc "Refresh site location hourly visitor rollups (optionally SITE_ID=..., FROM=..., TO=...)"
    task refresh_locations: :environment do
      refresh_hourly_rollups!(
        label: "location visitor",
        earliest_at: ->(site_id) { Analytics::FactStore.visit_relation(site: site_id).minimum(:started_at) },
        refresh_range: ->(site_id, range) { Analytics::SiteLocationHourlyVisitorRollup.refresh_range!(site: site_id, range:) }
      )
    end

    desc "Refresh site page hourly rollups (optionally SITE_ID=..., FROM=..., TO=...)"
    task refresh_pages: :environment do
      refresh_hourly_rollups!(
        label: "page",
        earliest_at: ->(site_id) { Analytics::FactStore.pageview_relation(site: site_id).minimum(:time) },
        refresh_range: ->(site_id, range) { Analytics::SitePageHourlyRollup.refresh_range!(site: site_id, range:) }
      )
    end
  end
end

def refresh_hourly_rollups!(label:, earliest_at:, refresh_range:)
  sites = Analytics::Site.active.order(:id)
  sites = sites.where(id: ENV["SITE_ID"]) if ENV["SITE_ID"].present?

  if sites.none?
    puts "No analytics sites matched."
    return
  end

  sites.find_each do |site|
    from = parse_rollup_time(ENV["FROM"]) || earliest_at.call(site.id)
    to = parse_rollup_time(ENV["TO"]) || Time.zone.now

    if from.blank? || to.blank? || from > to
      puts "Skipping #{label} rollups for site #{site.id} (#{site.name}) because the range is empty."
      next
    end

    range = from.beginning_of_hour..to.beginning_of_hour
    puts "Refreshing #{label} hourly rollups for site #{site.id} (#{site.name}) from #{range.begin.iso8601} to #{range.end.iso8601}"
    refresh_range.call(site.id, range)
  end
end

def parse_rollup_time(value)
  return if value.blank?

  Time.zone.parse(value.to_s)
rescue ArgumentError, TypeError
  nil
end
