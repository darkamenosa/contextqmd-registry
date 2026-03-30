# frozen_string_literal: true

require "cgi"
require "json"
require "net/http"
require "uri"

class Analytics::GoogleSearchConsole::Client
  Error = Class.new(StandardError)

  VERIFIED_PERMISSION_LEVELS = %w[siteOwner siteFullUser siteRestrictedUser].freeze
  AUTH_BASE_URL = "https://accounts.google.com/o/oauth2/v2/auth"
  TOKEN_URL = URI("https://oauth2.googleapis.com/token")
  USERINFO_URL = URI("https://www.googleapis.com/oauth2/v3/userinfo")
  SITES_URL = URI("https://www.googleapis.com/webmasters/v3/sites")
  SCOPES = [
    "openid",
    "email",
    "https://www.googleapis.com/auth/webmasters.readonly"
  ].freeze

  def initialize(redirect_uri: nil)
    @redirect_uri = redirect_uri
    @client_id = Analytics::GoogleSearchConsole::Configuration.client_id
    @client_secret = Analytics::GoogleSearchConsole::Configuration.client_secret
  end

  def authorization_url(state:)
    raise Error, "Google Search Console is not configured." unless configured?

    query = URI.encode_www_form(
      client_id: @client_id,
      redirect_uri: @redirect_uri,
      response_type: "code",
      access_type: "offline",
      prompt: "consent select_account",
      include_granted_scopes: "true",
      scope: SCOPES.join(" "),
      state: state
    )

    "#{AUTH_BASE_URL}?#{query}"
  end

  def exchange_code!(code)
    post_form(
      TOKEN_URL,
      client_id: @client_id,
      client_secret: @client_secret,
      code: code,
      grant_type: "authorization_code",
      redirect_uri: @redirect_uri
    )
  end

  def refresh_access_token!(refresh_token)
    post_form(
      TOKEN_URL,
      client_id: @client_id,
      client_secret: @client_secret,
      refresh_token: refresh_token,
      grant_type: "refresh_token"
    )
  end

  def fetch_user_profile(access_token)
    get_json(USERINFO_URL, access_token:)
  end

  def list_verified_properties(access_token)
    body = get_json(SITES_URL, access_token:)

    Array(body["siteEntry"]).filter_map do |entry|
      permission_level = entry["permissionLevel"].to_s
      identifier = entry["siteUrl"].to_s.strip
      next if identifier.blank? || !VERIFIED_PERMISSION_LEVELS.include?(permission_level)

      {
        identifier: identifier,
        type: property_type(identifier),
        permission_level: permission_level,
        label: property_label(identifier)
      }
    end.sort_by { |property| [ property[:type], property[:label], property[:identifier] ] }
  end

  def query_search_analytics(
    access_token,
    property_identifier:,
    start_date:,
    end_date:,
    dimensions:,
    row_limit:,
    start_row: 0,
    dimension_filters: nil,
    search_type: nil
  )
    uri = URI("https://www.googleapis.com/webmasters/v3/sites/#{CGI.escape(property_identifier)}/searchAnalytics/query")
    payload = {
      startDate: start_date.to_date.iso8601,
      endDate: end_date.to_date.iso8601,
      dimensions: Array(dimensions),
      rowLimit: row_limit.to_i,
      startRow: start_row.to_i
    }
    payload[:type] = search_type if search_type.present?
    if dimension_filters.present?
      payload[:dimensionFilterGroups] = [
        {
          groupType: "and",
          filters: dimension_filters
        }
      ]
    end

    request_json(Net::HTTP::Post.new(uri), uri) do |request|
      request["Authorization"] = "Bearer #{access_token}"
      request["Content-Type"] = "application/json"
      request.body = JSON.dump(payload)
    end
  end

  private
    def configured?
      @client_id.present? && @client_secret.present?
    end

    def property_type(identifier)
      identifier.start_with?("sc-domain:") ? "domain" : "url_prefix"
    end

    def property_label(identifier)
      return identifier.delete_prefix("sc-domain:") if identifier.start_with?("sc-domain:")

      uri = URI.parse(identifier)
      "#{uri.host}#{uri.path.presence == "/" ? nil : uri.path}"
    rescue URI::InvalidURIError
      identifier
    end

    def get_json(uri, access_token:)
      request_json(Net::HTTP::Get.new(uri), uri) do |request|
        request["Authorization"] = "Bearer #{access_token}"
      end
    end

    def post_form(uri, params)
      request_json(Net::HTTP::Post.new(uri), uri) do |request|
        request["Content-Type"] = "application/x-www-form-urlencoded"
        request.body = URI.encode_www_form(params)
      end
    end

    def request_json(request, uri)
      yield(request) if block_given?

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 20) do |http|
        http.request(request)
      end

      body = response.body.to_s
      parsed = body.present? ? JSON.parse(body) : {}

      return parsed if response.is_a?(Net::HTTPSuccess)

      error_message =
        if parsed.is_a?(Hash)
          parsed_error = parsed["error"]
          parsed.dig("error", "message") ||
            parsed["error_description"] ||
            (parsed_error if parsed_error.is_a?(String))
        end

      error_message ||= "Google Search Console request failed."
      raise Error, error_message
    rescue JSON::ParserError
      raise Error, "Google Search Console returned an invalid response."
    rescue Timeout::Error, Errno::ECONNRESET, Errno::ETIMEDOUT, SocketError => e
      raise Error, "Google Search Console request failed: #{e.class.name.demodulize.underscore.humanize.downcase}."
    end
end
