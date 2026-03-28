# frozen_string_literal: true

class Analytics::ProfileSessionsDatasetQuery < Analytics::DatasetQuery
  include Analytics::StorageBacked

  def initialize(profile:, limit:, page:)
    super(query: Analytics::Query.new, limit:, page:)
    @profile = profile
  end

  def page_records
    adapter.page_records
  end

  def has_more?
    adapter.has_more?
  end

  private
    attr_reader :profile

    def adapter_arguments
      { profile: profile, limit: limit, page: page }
    end
end
