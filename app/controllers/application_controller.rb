# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Authentication
  include Authorization
  include ErrorHandling
  include Analytics::HostIntegration
  include CurrentRequest
  include CurrentTimezone
  include SetPlatform
  include RoutingHeaders
  include RequestForgeryProtection

  etag { "v1" }
  etag { request.inertia? }
  allow_browser versions: :modern

  before_action :redirect_trailing_slash
  after_action :dedupe_vary_header

  def append_info_to_payload(payload)
    super
    payload[:cache_control] = response.headers["Cache-Control"]
  end

  private

    def merge_vary_header!(header)
      existing = response.headers["Vary"].to_s.split(",").map(&:strip).reject(&:blank?)
      return if existing.include?(header)

      response.headers["Vary"] = [ *existing, header ].join(", ")
    end

    def dedupe_vary_header
      values = response.headers["Vary"].to_s.split(",").map(&:strip).reject(&:blank?)
      return if values.empty?

      response.headers["Vary"] = values.each_with_object([]) do |value, unique|
        unique << value unless unique.any? { |existing| existing.casecmp?(value) }
      end.join(", ")
    end

    # Prevent duplicate content from trailing-slash URLs (preserves query params)
    def redirect_trailing_slash
      return if mounted_root_request?

      if request.get? && request.path.length > 1 && request.path.end_with?("/")
        path = request.path.chomp("/")
        path = "#{path}?#{request.query_string}" if request.query_string.present?
        redirect_to path, status: :moved_permanently
      end
    end

    def mounted_root_request?
      request.path_info == "/" && request.script_name.present?
    end
end
