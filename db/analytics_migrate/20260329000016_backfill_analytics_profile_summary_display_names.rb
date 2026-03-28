# frozen_string_literal: true

require "zlib"

class BackfillAnalyticsProfileSummaryDisplayNames < ActiveRecord::Migration[8.1]
  class MigrationAnalyticsProfile < ActiveRecord::Base
    self.table_name = "analytics_profiles"
  end

  class MigrationAnalyticsProfileSummary < ActiveRecord::Base
    self.table_name = "analytics_profile_summaries"
  end

  PROFILE_NAME_ADJECTIVES = %w[
    amber
    black
    blue
    bronze
    coral
    cyan
    emerald
    fuchsia
    gold
    indigo
    magenta
    mint
    pink
    silver
    teal
    turquoise
  ].freeze

  PROFILE_NAME_ANIMALS = %w[
    badger
    crane
    emu
    falcon
    fox
    gecko
    ibex
    jay
    lynx
    nightingale
    octopus
    otter
    perch
    scorpion
    sturgeon
    wildcat
  ].freeze

  def up
    say_with_time "Backfilling analytics profile summary display names" do
      stale_summaries.in_batches(of: 200) do |relation|
        summaries = relation.to_a
        profiles_by_id = MigrationAnalyticsProfile.where(id: summaries.map(&:analytics_profile_id)).index_by(&:id)

        summaries.each do |summary|
          profile = profiles_by_id[summary.analytics_profile_id]
          next if profile.blank?

          display_name = resolved_display_name(profile)
          search_text = build_search_text(summary, display_name)

          summary.update_columns(
            display_name: display_name,
            search_text: search_text,
            updated_at: Time.current
          )
        end
      end
    end
  end

  def down
  end

  private
    def stale_summaries
      MigrationAnalyticsProfileSummary.where("COALESCE(display_name, '') = '' OR COALESCE(search_text, '') = ''")
    end

    def resolved_display_name(profile)
      profile.traits.to_h["display_name"].to_s.presence ||
        generated_display_name(profile.public_id || profile.id)
    rescue StandardError
      generated_display_name(profile.public_id || profile.id)
    end

    def build_search_text(summary, display_name)
      [
        display_name,
        summary.email,
        summary.latest_country_name,
        summary.latest_city,
        summary.latest_region,
        summary.latest_source,
        summary.latest_browser,
        summary.latest_os,
        summary.latest_device_type,
        summary.latest_current_page
      ].filter_map { |value| value.to_s.strip.presence }.uniq.join(" ")
    end

    def generated_display_name(seed)
      digest = Zlib.crc32(seed.to_s)
      adjective = PROFILE_NAME_ADJECTIVES[digest % PROFILE_NAME_ADJECTIVES.length]
      animal = PROFILE_NAME_ANIMALS[(digest / PROFILE_NAME_ADJECTIVES.length) % PROFILE_NAME_ANIMALS.length]

      "#{adjective} #{animal}"
    end
end
