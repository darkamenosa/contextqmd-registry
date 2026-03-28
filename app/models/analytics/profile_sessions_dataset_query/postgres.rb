# frozen_string_literal: true

class Analytics::ProfileSessionsDatasetQuery::Postgres < Analytics::DatasetQuery
  def initialize(profile:, limit:, page:)
    super(query: Analytics::Query.new, limit:, page:)
    @profile = profile
  end

  def page_records
    @page_records ||= begin
      records, @has_more = fetch_page(
        AnalyticsProfileSession
          .where(analytics_profile_id: profile.id)
          .order(started_at: :desc, id: :desc)
      )
      records
    end
  end

  def has_more?
    page_records
    @has_more
  end

  private
    attr_reader :profile
end
