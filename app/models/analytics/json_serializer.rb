# frozen_string_literal: true

class Analytics::JsonSerializer
  class << self
    def call(value)
      case value
      when Array
        value.map { |item| call(item) }
      when Hash
        value.each_with_object({}) do |(key, val), memo|
          memo[key.to_s.camelize(:lower)] = call(val)
        end
      else
        value
      end
    end
  end
end
