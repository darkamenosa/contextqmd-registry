# frozen_string_literal: true

module Analytics::Search
  class << self
    def contains_pattern(value)
      "%#{ActiveRecord::Base.sanitize_sql_like(value.to_s.downcase)}%"
    end
  end
end
