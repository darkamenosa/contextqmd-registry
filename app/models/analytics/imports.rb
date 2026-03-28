# frozen_string_literal: true

module Analytics::Imports
  class << self
    def skip_reason(query = nil)
      wrapped_query = Analytics::Query.wrap(query || {})
      wrapped_query.with_imported? ? "not_supported" : nil
    end

    def pages_aggregates(_range)
      {}
    end

    def entry_aggregates(_range)
      {}
    end

    def exit_aggregates(_range)
      {}
    end
  end
end
