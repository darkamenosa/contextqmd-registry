# frozen_string_literal: true

class AnalyticsProfile::Resolution
  class << self
    def available?
      AnalyticsProfile.available? &&
        AnalyticsProfileKey.available? &&
        Ahoy::Visit.column_names.include?("analytics_profile_id") &&
        Ahoy::Visit.column_names.include?("browser_id")
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
      false
    end

    def resolve(visit:, browser_id:, strong_keys:, occurred_at: nil)
      return nil unless available?
      return nil if visit.blank?

      normalized_keys = AnalyticsProfileKey.normalize_strong_keys(strong_keys)
      activity_time = occurred_at || visit.started_at || Time.current
      previous_profile_id = visit.analytics_profile_id

      profile = AnalyticsProfile.transaction do
        profile = resolve_candidate_profile(
          site: visit.analytics_site,
          browser_id: browser_id,
          strong_keys: normalized_keys,
          occurred_at: activity_time,
          current_profile_id: previous_profile_id
        )
        profile.attach_strong_keys!(
          normalized_keys,
          observed_at: activity_time,
          identity_snapshot: visit.analytics_identity_snapshot
        )
        profile.record_visit!(visit, browser_id:, observed_at: activity_time)
        profile
      end

      visit.project_later(previous_profile_id: previous_profile_id)
      profile
    end

    private
      def resolve_candidate_profile(site:, browser_id:, strong_keys:, occurred_at:, current_profile_id:)
        strong_profiles = AnalyticsProfileKey.matching_profiles(strong_keys, site: site).to_a
        browser_profile = profile_for_last_browser_visit(browser_id, site: site)
        current_profile = current_profile_id.present? ? AnalyticsProfile.for_analytics_site(site).find_by(id: current_profile_id) : nil

        if strong_profiles.any?
          canonical = choose_canonical_profile(strong_profiles)
          (strong_profiles - [ canonical ]).each do |profile|
            canonical.merge_profile!(profile)
          end

          if should_merge_browser_profile?(
            browser_profile,
            canonical: canonical,
            current_profile: current_profile,
            occurred_at: occurred_at
          )
            canonical.merge_profile!(browser_profile)
          end

          canonical
        elsif browser_profile&.anonymous?
          browser_profile
        elsif current_profile&.anonymous?
          current_profile
        else
          AnalyticsProfile.create!(
            analytics_site: site,
            status: AnalyticsProfile::STATUS_ANONYMOUS,
            first_seen_at: occurred_at,
            last_seen_at: occurred_at,
            resolver_version: AnalyticsProfile::RESOLVER_VERSION
          )
        end
      end

      def profile_for_last_browser_visit(browser_id, site:)
        return nil if browser_id.blank?

        profile_id = Ahoy::Visit
          .for_analytics_site(site)
          .where(browser_id: browser_id)
          .where.not(analytics_profile_id: nil)
          .where(started_at: AnalyticsProfile::BROWSER_CONTINUITY_WINDOW.ago..)
          .order(started_at: :desc, id: :desc)
          .limit(1)
          .pick(:analytics_profile_id)

        profile_id ? AnalyticsProfile.canonical.for_analytics_site(site).find_by(id: profile_id) : nil
      end

      def should_merge_browser_profile?(browser_profile, canonical:, current_profile:, occurred_at:)
        return false if browser_profile.blank? || browser_profile == canonical || !browser_profile.anonymous?
        return true if current_profile.present? && current_profile == browser_profile

        window_start = occurred_at - Ahoy.visit_duration
        browser_profile.last_seen_at.present? && browser_profile.last_seen_at >= window_start
      end

      def choose_canonical_profile(profiles)
        profiles.min_by do |profile|
          [
            profile.anonymous? ? 1 : 0,
            profile.first_seen_at || Time.at(Float::INFINITY),
            profile.id
          ]
        end
      end
  end
end
