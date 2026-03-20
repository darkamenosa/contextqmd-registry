# frozen_string_literal: true

class AuthFailure < Devise::FailureApp
  def respond
    if request.headers["X-Inertia"]
      redirect
    else
      super
    end
  end

  def redirect_url
    new_identity_session_url(script_name: nil)
  end
end

Devise.setup do |config|
  require "devise/orm/active_record"

  config.mailer_sender = ENV.fetch("DEVISE_MAILER_SENDER", "ContextqmdRegistry <noreply@contextqmd_registry.app>")
  config.case_insensitive_keys = [ :email ]
  config.strip_whitespace_keys = [ :email ]
  config.skip_session_storage = [ :http_auth ]
  config.stretches = Rails.env.test? ? 1 : 12
  config.expire_all_remember_me_on_sign_out = true
  config.password_length = 6..128
  config.email_regexp = /\A[^@\s]+@[^@\s]+\z/
  config.sign_out_via = :delete
  config.reset_password_within = 6.hours
  config.responder.error_status = :unprocessable_entity
  config.responder.redirect_status = :see_other

  # Google OAuth
  google_client_id = ENV["GOOGLE_CLIENT_ID"] || Rails.application.credentials.dig(:google, :client_id)
  google_client_secret = ENV["GOOGLE_CLIENT_SECRET"] || Rails.application.credentials.dig(:google, :client_secret)

  if Rails.env.test?
    google_client_id ||= "test-client-id"
    google_client_secret ||= "test-client-secret"
  end

  if google_client_id.present? && google_client_secret.present?
    config.omniauth :google_oauth2, google_client_id, google_client_secret, prompt: "select_account"
  end

  config.warden do |manager|
    manager.failure_app = AuthFailure
  end
end
