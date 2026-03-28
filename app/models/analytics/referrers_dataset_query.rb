# frozen_string_literal: true

class Analytics::ReferrersDatasetQuery
  include Analytics::StorageBacked

  class << self
    def payload(query:, source:, limit: nil, page: nil, search: nil, order_by: nil)
      new(query:, source:, limit:, page:, search:, order_by:).payload
    end
  end

  def initialize(query:, source:, limit:, page:, search:, order_by:)
    @query = Analytics::Query.wrap(query)
    @source = source
    @limit = limit
    @page = page
    @search = search
    @order_by = order_by || @query.order_by
  end

  def payload
    adapter.payload
  end

  private
    attr_reader :query, :source, :limit, :page, :search, :order_by

    def adapter_arguments
      {
        query: query,
        source: source,
        limit: limit,
        page: page,
        search: search,
        order_by: order_by
      }
    end
end
