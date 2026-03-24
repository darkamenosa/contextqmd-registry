module Ahoy::Visit::UrlLabels
  extend ActiveSupport::Concern

  class_methods do
    # Normalize landing_page full URL to path+query (Plausible-style labels)
    def normalized_path_and_query(url)
      s = url.to_s.strip
      return nil if s.empty?
      begin
        uri = URI.parse(s)
        path = uri.path.presence || "/"
        q = uri.query.to_s
        q.present? ? "#{path}?#{q}" : path
      rescue URI::InvalidURIError
        s.start_with?("/") ? s : nil
      end
    end

    # Normalize landing_page full URL to pathname only (Plausible stores entry_page as path)
    def normalized_path_only(url)
      s = url.to_s.strip
      return nil if s.empty?
      begin
        uri = URI.parse(s)
        path = uri.path.presence || "/"
        path
      rescue URI::InvalidURIError
        s.start_with?("/") ? s.split("?").first : nil
      end
    end
  end
end
