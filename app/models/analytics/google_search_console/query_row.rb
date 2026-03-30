# frozen_string_literal: true

class Analytics::GoogleSearchConsole::QueryRow < AnalyticsRecord
  self.table_name = "analytics_google_search_console_query_rows"

  belongs_to :analytics_site,
    class_name: "Analytics::Site",
    inverse_of: :google_search_console_query_rows
  belongs_to :sync,
    class_name: "Analytics::GoogleSearchConsole::Sync",
    foreign_key: :analytics_google_search_console_sync_id,
    inverse_of: :query_rows

  before_validation :normalize_page!

  validates :analytics_site, :sync, :date, :search_type, :query, :page, presence: true

  scope :for_site, ->(site = ::Analytics::Current.site) { site.present? ? where(analytics_site_id: site.id) : none }
  scope :for_search_type, ->(search_type) { where(search_type: search_type.to_s) }
  scope :within_dates, ->(from_date, to_date) { where(date: from_date..to_date) }

  class << self
    def normalize_page_value(page)
      Analytics::Urls.normalized_path_only(page).presence || "/"
    end
  end

  private
    def normalize_page!
      self.page = self.class.normalize_page_value(page)
    end
end
