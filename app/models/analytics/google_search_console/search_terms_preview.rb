# frozen_string_literal: true

class Analytics::GoogleSearchConsole::SearchTermsPreview
  DEFAULT_LIMIT = 3
  MATCH_STRATEGIES = [
    { day_padding: 0, country: true, device: true },
    { day_padding: 0, country: true, device: false },
    { day_padding: 0, country: false, device: true },
    { day_padding: 0, country: false, device: false },
    { day_padding: 1, country: true, device: true },
    { day_padding: 1, country: true, device: false },
    { day_padding: 1, country: false, device: true },
    { day_padding: 1, country: false, device: false }
  ].freeze
  GOOGLE_LABEL = "Google"
  ORGANIC_MEDIUM = "organic"

  class << self
    def for_visit(visit, limit: DEFAULT_LIMIT)
      new(visit, limit: limit).results
    end
  end

  def initialize(visit, limit: DEFAULT_LIMIT)
    @visit = visit
    @limit = limit.to_i.positive? ? limit.to_i : DEFAULT_LIMIT
  end

  def results
    return [] unless eligible?

    MATCH_STRATEGIES.each do |strategy|
      rows = relation_for(strategy).to_a
      return build_results(rows) if rows.any?
    end

    []
  end

  private
    attr_reader :visit, :limit

    def eligible?
      site.present? &&
        landing_page.present? &&
        visit.started_at.present? &&
        google_source? &&
        !visit.source_paid?
    end

    def google_source?
      visit.source_label.to_s == GOOGLE_LABEL &&
        (
          visit.source_kind.to_s == "search" ||
          visit.utm_medium.to_s.downcase == ORGANIC_MEDIUM ||
          visit.referring_domain.to_s.downcase.include?("google.")
        )
    end

    def site
      visit.analytics_site || ::Analytics::Current.site
    end

    def landing_page
      @landing_page ||= Analytics::Urls.normalized_path_only(visit.landing_page).presence
    end

    def country
      @country ||= begin
        alpha2 = visit.respond_to?(:country_code) ? visit.country_code : nil
        alpha2 = Ahoy::Visit.normalize_country_code(alpha2.presence || visit.country)
        ISO3166::Country[alpha2]&.alpha3
      end
    end

    def device
      @device ||= begin
        case visit.device_type.to_s.downcase
        when "desktop" then "desktop"
        when "mobile" then "mobile"
        when "tablet" then "tablet"
        else nil
        end
      end
    end

    def relation_for(strategy)
      padding = strategy.fetch(:day_padding)
      from_date = visit.started_at.to_date - padding.days
      to_date = visit.started_at.to_date + padding.days

      relation = Analytics::GoogleSearchConsole::QueryRow
        .for_site(site)
        .for_search_type(Analytics::GoogleSearchConsole::Syncer::DEFAULT_SEARCH_TYPE)
        .within_dates(from_date, to_date)
        .where(page: landing_page)

      relation = relation.where(country: country) if strategy[:country] && country.present?
      relation = relation.where(device: device) if strategy[:device] && device.present?

      relation
        .group(:query)
        .select(
          "query AS label",
          "SUM(clicks) AS clicks",
          "SUM(impressions) AS impressions"
        )
        .order(Arel.sql("SUM(clicks) DESC, SUM(impressions) DESC, query ASC"))
        .limit(limit)
    end

    def build_results(rows)
      scores = rows.map { |row| row.clicks.to_f.positive? ? row.clicks.to_f : row.impressions.to_f }
      total = scores.sum
      return [] if total <= 0

      probabilities = rows.each_with_index.map do |row, index|
        if index == rows.length - 1
          100 - rows.each_with_index.sum { |_, inner_index| inner_index < index ? probability_for(scores[inner_index], total) : 0 }
        else
          probability_for(scores[index], total)
        end
      end

      rows.each_with_index.map do |row, index|
        {
          "label" => row.label.to_s,
          "probability" => probabilities[index].clamp(1, 100)
        }
      end
    end

    def probability_for(score, total)
      ((score / total) * 100.0).round
    end
end
