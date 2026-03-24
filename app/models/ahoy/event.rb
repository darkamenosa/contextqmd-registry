class Ahoy::Event < AnalyticsRecord
  include Ahoy::QueryMethods
  include Ahoy::Event::Filters

  self.table_name = "ahoy_events"

  belongs_to :visit
  belongs_to :user, class_name: "::Identity", optional: true
end
