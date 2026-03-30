# frozen_string_literal: true

namespace :analytics do
  desc "Bootstrap the default singleton analytics site"
  task :bootstrap, [ :host, :name ] => :environment do |_task, args|
    host = args[:host].presence || Analytics::Configuration.default_site_host || "localhost"
    name = args[:name].presence || Analytics::Configuration.default_site_name(request_host: host) || host
    site = Analytics::Bootstrap.ensure_default_site!(host: host, name: name)

    puts "Analytics site ready:"
    puts "  id: #{site.public_id}"
    puts "  name: #{site.name}"
    puts "  host: #{site.canonical_hostname}"
  end

  desc "Repair analytics site scope for profiles, projections, and singleton unscoped rows"
  task repair_site_scope: :environment do
    sites = Analytics::Site.active.order(:id).to_a

    if sites.empty?
      puts "No analytics sites found."
      next
    end

    sites.each do |site|
      puts "Repairing analytics site scope for #{site.name} (#{site.id})"
      repair_analytics_site_scope!(site)
    end

    puts "Done."
  end
end

def repair_analytics_site_scope!(site)
  site_id = site.id
  primary_boundary = site.boundaries.find_by(primary: true)
  if primary_boundary.blank? && site.canonical_hostname.present?
    primary_boundary = site.boundaries.create!(
      host: Analytics::SiteBoundary.normalize_host(site.canonical_hostname),
      path_prefix: "/",
      priority: 0,
      primary: true
    )
  end
  primary_boundary_id = primary_boundary&.id
  singleton = Analytics::Site.active.where.not(id: site_id).none?

  AnalyticsProfile.transaction do
    if singleton
      Ahoy::Visit.connection.execute(<<~SQL.squish)
        UPDATE ahoy_visits
        SET analytics_site_id = #{site_id.to_i},
            analytics_site_boundary_id = COALESCE(analytics_site_boundary_id, #{primary_boundary_id || 'NULL'})
        WHERE analytics_site_id IS NULL
      SQL

      Ahoy::Event.connection.execute(<<~SQL.squish)
        UPDATE ahoy_events
        SET analytics_site_id = COALESCE(ahoy_events.analytics_site_id, ahoy_visits.analytics_site_id, #{site_id.to_i}),
            analytics_site_boundary_id = COALESCE(ahoy_events.analytics_site_boundary_id, ahoy_visits.analytics_site_boundary_id, #{primary_boundary_id || 'NULL'})
        FROM ahoy_visits
        WHERE ahoy_events.visit_id = ahoy_visits.id
          AND (ahoy_events.analytics_site_id IS NULL OR ahoy_events.analytics_site_boundary_id IS NULL)
      SQL
    end

    AnalyticsProfile.connection.execute(<<~SQL.squish)
      UPDATE analytics_profiles
      SET analytics_site_id = resolved.analytics_site_id,
          updated_at = CURRENT_TIMESTAMP
      FROM (
        SELECT DISTINCT ON (analytics_profile_id)
          analytics_profile_id,
          analytics_site_id
        FROM ahoy_visits
        WHERE analytics_profile_id IS NOT NULL
          AND analytics_site_id = #{site_id.to_i}
        ORDER BY analytics_profile_id, started_at DESC, id DESC
      ) resolved
      WHERE analytics_profiles.id = resolved.analytics_profile_id
        AND analytics_profiles.analytics_site_id IS NULL
    SQL

    AnalyticsProfileKey.connection.execute(<<~SQL.squish)
      UPDATE analytics_profile_keys
      SET analytics_site_id = analytics_profiles.analytics_site_id,
          updated_at = CURRENT_TIMESTAMP
      FROM analytics_profiles
      WHERE analytics_profile_keys.analytics_profile_id = analytics_profiles.id
        AND analytics_profiles.analytics_site_id = #{site_id.to_i}
        AND analytics_profile_keys.analytics_site_id IS NULL
    SQL

    AnalyticsProfileSummary.connection.execute(<<~SQL.squish)
      UPDATE analytics_profile_summaries
      SET analytics_site_id = analytics_profiles.analytics_site_id,
          updated_at = CURRENT_TIMESTAMP
      FROM analytics_profiles
      WHERE analytics_profile_summaries.analytics_profile_id = analytics_profiles.id
        AND analytics_profiles.analytics_site_id = #{site_id.to_i}
        AND analytics_profile_summaries.analytics_site_id IS NULL
    SQL

    AnalyticsProfileSession.connection.execute(<<~SQL.squish)
      UPDATE analytics_profile_sessions
      SET analytics_site_id = analytics_profiles.analytics_site_id,
          updated_at = CURRENT_TIMESTAMP
      FROM analytics_profiles
      WHERE analytics_profile_sessions.analytics_profile_id = analytics_profiles.id
        AND analytics_profiles.analytics_site_id = #{site_id.to_i}
        AND analytics_profile_sessions.analytics_site_id IS NULL
    SQL
  end
end
