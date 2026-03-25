# frozen_string_literal: true

require "openssl"
require Rails.root.join("lib/client_ip")

module AnalyticsAnonymousIdentity
  extend self

  PURPOSE = "analytics-anonymous-identity"
  ROTATION_PERIOD = 24.hours
  TOKEN_LENGTH = 64

  def current(request, now: Time.current)
    token_for(request, bucket_start(now))
  end

  def previous(request, now: Time.current)
    token_for(request, bucket_start(now) - ROTATION_PERIOD)
  end

  def tokens(request, now: Time.current)
    [ current(request, now: now), previous(request, now: now) ].compact.uniq
  end

  private
    def token_for(request, bucket)
      signature = request_signature(request)
      return if signature.blank?

      salt = OpenSSL::HMAC.hexdigest("SHA256", secret_key, "#{PURPOSE}/#{bucket.to_i}")
      OpenSSL::HMAC.hexdigest("SHA256", salt, signature).first(TOKEN_LENGTH)
    rescue StandardError
      nil
    end

    def request_signature(request)
      return if request.nil?

      client_ip = ClientIp.best_effort(request) || request&.remote_ip
      return if client_ip.blank?

      masked_ip = Ahoy.mask_ip(client_ip)
      host = normalized_host(request)
      user_agent = request.user_agent.to_s

      [ masked_ip, host, user_agent ].join("\0")
    rescue StandardError
      nil
    end

    def normalized_host(request)
      request.host.to_s.downcase.sub(/\Awww\./, "")
    end

    def bucket_start(now)
      now.utc.beginning_of_day
    end

    def secret_key
      @secret_key ||= Rails.application.key_generator.generate_key(PURPOSE, 32)
    end
end
