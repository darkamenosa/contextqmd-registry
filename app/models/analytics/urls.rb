# frozen_string_literal: true

module Analytics::Urls
  class << self
    def normalized_path_and_query(url)
      value = url.to_s.strip
      return nil if value.empty?

      begin
        uri = URI.parse(value)
        path = uri.path.presence || "/"
        query = uri.query.to_s
        query.present? ? "#{path}?#{query}" : path
      rescue URI::InvalidURIError
        value.start_with?("/") ? value : nil
      end
    end

    def normalized_path_only(url)
      value = url.to_s.strip
      return nil if value.empty?

      begin
        uri = URI.parse(value)
        uri.path.presence || "/"
      rescue URI::InvalidURIError
        value.start_with?("/") ? value.split("?").first : nil
      end
    end
  end
end
