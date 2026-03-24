module Ahoy::Visit::CacheKey
  extend ActiveSupport::Concern

  class_methods do
    def analytics_data_version
      Rails.cache.fetch("analytics:data-version:v1", expires_in: 15.seconds, race_condition_ttl: 5.seconds) do
        visit_time = Ahoy::Visit.maximum(:started_at)
        event_time = Ahoy::Event.maximum(:time)

        if visit_time || event_time
          [ visit_time, event_time ].compact.map { |time| time.utc.to_f }.max
        else
          [ Ahoy::Visit.maximum(:id), Ahoy::Event.maximum(:id) ].compact.max.to_i
        end
      end
    end
  end
end
