# frozen_string_literal: true

class Analytics::TopStatsQuery
  include Analytics::StorageBacked

  class << self
    def payload(query:)
      new(query:).payload
    end
  end

  def initialize(query:)
    @query = Analytics::Query.wrap(query)
  end

  def payload
    adapter.payload
  end

  private
    attr_reader :query

    def adapter_arguments
      { query: query }
    end
end
