# frozen_string_literal: true

module Analytics::Lists
  class << self
    def normalize_strings(values)
      Array(values).filter_map do |value|
        normalized = value.to_s.strip
        normalized.presence
      end.uniq.sort
    end
  end
end
