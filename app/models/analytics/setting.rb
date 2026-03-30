# frozen_string_literal: true

class Analytics::Setting < AnalyticsRecord
  self.table_name = "analytics_settings"

  belongs_to :analytics_site, class_name: "Analytics::Site", optional: true

  validates :key, presence: true, uniqueness: { scope: :analytics_site_id }

  scope :global, -> { where(analytics_site_id: nil) }
  scope :for_analytics_site, ->(site = ::Analytics::Current.site_or_default) { Analytics::Scope.apply(all, site:) }

  class << self
    def effective_scope(site = ::Analytics::Current.site_or_default)
      site_scope = for_analytics_site(site)
      return site_scope if site.present? && site_scope.exists?

      global
    end

    def configured?(key, site: ::Analytics::Current.site_or_default)
      effective_record(key, site:).present?
    end

    def get_json(key, fallback: nil, site: ::Analytics::Current.site_or_default)
      rec = effective_record(key, site:)
      return fallback if rec.nil? || rec.value.blank?

      JSON.parse(rec.value)
    rescue JSON::ParserError
      fallback
    end

    def get_bool(key, fallback: false, site: ::Analytics::Current.site_or_default)
      rec = effective_record(key, site:)
      return fallback if rec.nil?

      ActiveModel::Type::Boolean.new.cast(rec.value)
    end

    def set_json(key, value, site: ::Analytics::Current.site_or_default)
      rec = find_or_initialize_by(key: key, analytics_site_id: site&.id)
      rec.value = value.to_json
      rec.save!
    end

    def set_bool(key, value, site: ::Analytics::Current.site_or_default)
      rec = find_or_initialize_by(key: key, analytics_site_id: site&.id)
      rec.value = ActiveModel::Type::Boolean.new.cast(value) ? "true" : "false"
      rec.save!
    end

    private
      def effective_record(key, site: ::Analytics::Current.site_or_default)
        if site.present?
          site_record = find_by(key:, analytics_site_id: site.id)
          return site_record if site_record
        end

        find_by(key:, analytics_site_id: nil)
      end
  end
end
