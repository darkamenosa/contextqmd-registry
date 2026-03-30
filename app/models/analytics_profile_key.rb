# frozen_string_literal: true

class AnalyticsProfileKey < AnalyticsRecord
  belongs_to :analytics_profile
  belongs_to :analytics_site, class_name: "Analytics::Site", optional: true

  before_validation :assign_seen_timestamps

  validates :kind, presence: true
  validates :value, presence: true
  validates :first_seen_at, presence: true
  validates :last_seen_at, presence: true

  def self.available?
    connection.data_source_exists?(table_name)
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
    false
  end

  def self.matching_profiles(strong_keys, site: ::Analytics::Current.site)
    return AnalyticsProfile.none unless available?

    normalized_keys = normalize_strong_keys(strong_keys)
    return AnalyticsProfile.none if normalized_keys.empty?

    matching_keys = none

    normalized_keys.each do |key|
      matching_keys = matching_keys.or(where(kind: key[:kind], value: key[:value]))
    end

    AnalyticsProfile.canonical.for_analytics_site(site).where(id: matching_keys.select(:analytics_profile_id).distinct)
  end

  def self.normalize_strong_keys(strong_keys)
    pairs =
      case strong_keys
      when Array
        strong_keys.filter_map do |key|
          next unless key.respond_to?(:to_h)

          normalized_key = key.to_h.symbolize_keys.slice(:kind, :value)
          next if normalized_key[:kind].blank? || normalized_key[:value].blank?

          [ normalized_key[:kind], normalized_key[:value] ]
        end
      else
        strong_keys.to_h.to_a
      end

    pairs.each_with_object([]) do |(kind, value), keys|
      next if kind.blank? || value.blank?

      keys << { kind: kind.to_s, value: value.to_s }
    end
  end

  private
    def assign_seen_timestamps
      now = Time.current
      self.first_seen_at ||= now
      self.last_seen_at ||= self.first_seen_at || now
      self.analytics_site_id ||= analytics_profile&.analytics_site_id
    end
end
