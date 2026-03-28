# frozen_string_literal: true

class Analytics::DatasetQuery
  attr_reader :query, :limit, :page, :search

  def initialize(query:, limit:, page:, search: nil)
    @query = Analytics::Query.wrap(query)
    @limit = limit.to_i
    @page = page.to_i
    @search = search
  end

  def offset
    [ page - 1, 0 ].max * limit
  end

  def fetch_page(relation)
    records = relation.offset(offset).limit(limit + 1).to_a
    [
      records.first(limit),
      records.length > limit
    ]
  end
end
