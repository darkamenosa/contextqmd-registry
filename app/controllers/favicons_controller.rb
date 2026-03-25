# frozen_string_literal: true

class FaviconsController < ApplicationController
  allow_unauthenticated_access
  skip_forgery_protection

  def show
    payload = Analytics::SourceFavicon.fetch(params[:source])

    if payload.present?
      headers_to_forward(payload.fetch(:headers, {})).each do |key, values|
        response.set_header(key, Array(values).join(", "))
      end

      body = payload.fetch(:body).to_s
      response.set_header("Content-Security-Policy", "script-src 'none'")
      response.set_header("Content-Disposition", "attachment")
      content_type = if body.lstrip.start_with?("<svg")
        "image/svg+xml"
      else
        response.headers["Content-Type"].presence || "application/octet-stream"
      end

      send_data(body, disposition: "attachment", type: content_type)
    else
      send_placeholder
    end
  end

  private
    def send_placeholder
      response.set_header("Cache-Control", "public, max-age=2592000")
      render plain: Analytics::SourceFavicon.placeholder_svg, content_type: "image/svg+xml"
    end

    def headers_to_forward(headers)
      headers.each_with_object({}) do |(key, values), memo|
        normalized_key = key.to_s.downcase
        next unless Analytics::SourceFavicon::FORWARDED_HEADERS.include?(normalized_key)

        memo[normalized_key.split("-").map(&:capitalize).join("-")] = values
      end
    end
end
