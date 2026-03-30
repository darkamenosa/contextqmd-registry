# frozen_string_literal: true

class Analytics::ProfileSessionsDatasetQuery::Postgres < Analytics::DatasetQuery
  def initialize(profile:, limit:, page:, date: nil)
    super(query: Analytics::Query.new, limit:, page:)
    @profile = profile
    @date = date
  end

  def page_records
    @page_records ||= begin
      scope = AnalyticsProfileSession.for_analytics_site(profile.analytics_site).where(analytics_profile_id: profile.id)
      scope = scope.where(started_at: date.beginning_of_day..date.end_of_day) if date
      records, @has_more = fetch_page(
        scope.order(started_at: :desc, id: :desc)
      )
      records
    end
  end

  def has_more?
    page_records
    @has_more
  end

  private
    attr_reader :profile, :date
end
