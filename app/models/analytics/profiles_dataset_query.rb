# frozen_string_literal: true

class Analytics::ProfilesDatasetQuery < Analytics::DatasetQuery
  include Analytics::StorageBacked

  def page_records
    adapter.page_records
  end

  def has_more?
    adapter.has_more?
  end

  def summaries_by_profile
    adapter.summaries_by_profile
  end

  def latest_visits_by_profile
    adapter.latest_visits_by_profile
  end

  def total_visits_by_profile
    adapter.total_visits_by_profile
  end

  private
    def adapter_arguments
      { query: query, limit: limit, page: page, search: search }
    end
end
