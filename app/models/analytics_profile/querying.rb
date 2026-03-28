# frozen_string_literal: true

require "zlib"

module AnalyticsProfile::Querying
  extend ActiveSupport::Concern

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

  class_methods do
    def live_payload(now: Time.zone.now, window: 5.minutes)
      AnalyticsProfile::Live.payload(now:, window:)
    end

    def live_sessions(now: Time.zone.now, window: 5.minutes)
      AnalyticsProfile::Live.sessions(now:, window:)
    end

    def profiles_payload(query, limit:, page:, search: nil)
      AnalyticsProfile::Directory.payload(query:, limit:, page:, search:)
    end

    def journey_payload(public_id, query = nil)
      AnalyticsProfile::Journey.payload(public_id:, query:)
    end

    def sessions_list_payload(public_id, limit:, page:, date: nil)
      AnalyticsProfile::Journey.sessions_list_payload(
        public_id:,
        limit:,
        page:,
        date:
      )
    end

    def session_payload(public_id, visit_id, query = nil)
      AnalyticsProfile::Journey.session_payload(public_id:, visit_id:, query:)
    end

    def generated_display_name(seed)
      digest = Zlib.crc32(seed.to_s)
      adjective = PROFILE_NAME_ADJECTIVES[digest % PROFILE_NAME_ADJECTIVES.length]
      animal = PROFILE_NAME_ANIMALS[(digest / PROFILE_NAME_ADJECTIVES.length) % PROFILE_NAME_ANIMALS.length]

      "#{adjective} #{animal}"
    end
  end

  def display_name
    traits.to_h["display_name"].presence || self.class.generated_display_name(public_id || id)
  end

  def email
    traits.to_h["email"].presence
  end
end
