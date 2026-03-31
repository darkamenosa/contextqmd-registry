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
      scope = Ahoy::Visit.order(:id)
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
  end
end
