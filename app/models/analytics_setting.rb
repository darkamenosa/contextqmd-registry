# frozen_string_literal: true

class AnalyticsSetting < AnalyticsRecord
  self.table_name = "analytics_settings"

  validates :key, presence: true, uniqueness: true

  def self.get_bool(key, fallback: false)
    rec = find_by(key: key)
    return fallback if rec.nil?
    ActiveModel::Type::Boolean.new.cast(rec.value)
  end

  def self.set_bool(key, value)
    rec = find_or_initialize_by(key: key)
    rec.value = ActiveModel::Type::Boolean.new.cast(value) ? "true" : "false"
    rec.save!
  end
end
