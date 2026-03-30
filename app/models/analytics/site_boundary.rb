# frozen_string_literal: true

class Analytics::SiteBoundary < AnalyticsRecord
  self.table_name = "analytics_site_boundaries"

  belongs_to :site,
    class_name: "Analytics::Site",
    foreign_key: :analytics_site_id,
    inverse_of: :boundaries

  before_validation :normalize_fields

  validates :host, presence: true
  validates :path_prefix, presence: true, uniqueness: { scope: :host }

  class << self
    def resolve(host:, path: nil)
      normalized_host = normalize_host(host)
      return if normalized_host.blank?

      normalized_path = normalize_path_prefix(path)

      where(host: normalized_host)
        .order(primary: :desc, priority: :desc, id: :asc)
        .to_a
        .select { |boundary| boundary.matches_path?(normalized_path) }
        .max_by { |boundary| [ boundary.path_prefix.to_s.length, boundary.priority.to_i, boundary.primary? ? 1 : 0 ] }
    end

    def normalize_host(host)
      value = host.to_s.strip.downcase
      value = value.sub(/:\d+\z/, "")
      value.presence
    end

    def normalize_path_prefix(path_prefix)
      value = extract_path(path_prefix)
      value = "/" if value.blank?
      value = "/#{value}" unless value.start_with?("/")
      value = value.gsub(%r{/+}, "/")
      value = value.sub(%r{/+\z}, "")
      value.presence || "/"
    end

    private
      def extract_path(value)
        raw = value.to_s.strip
        return "" if raw.blank?

        if raw.match?(/\Ahttps?:\/\//i)
          URI.parse(raw).path.to_s
        else
          raw
        end
      rescue URI::InvalidURIError
        raw
      end
  end

  def matches_path?(path)
    normalized_path = self.class.normalize_path_prefix(path)
    return true if path_prefix == "/"

    normalized_path == path_prefix || normalized_path.start_with?("#{path_prefix}/")
  end

  private
    def normalize_fields
      self.host = self.class.normalize_host(host)
      self.path_prefix = self.class.normalize_path_prefix(path_prefix)
      self.priority = priority.to_i
      self.primary = !!self.primary
    end
end
