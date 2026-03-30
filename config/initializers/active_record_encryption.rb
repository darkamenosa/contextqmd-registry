# frozen_string_literal: true

credentials = Rails.application.credentials.dig(:active_record_encryption) || {}
secret_key_base = Rails.application.secret_key_base.to_s

derive_encryption_secret = lambda do |label|
  OpenSSL::HMAC.hexdigest("SHA256", secret_key_base, "active_record_encryption/#{label}")
end

Rails.application.config.active_record.encryption.primary_key ||=
  ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"] ||
  credentials[:primary_key] ||
  derive_encryption_secret.call("primary_key")

Rails.application.config.active_record.encryption.deterministic_key ||=
  ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"] ||
  credentials[:deterministic_key] ||
  derive_encryption_secret.call("deterministic_key")

Rails.application.config.active_record.encryption.key_derivation_salt ||=
  ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"] ||
  credentials[:key_derivation_salt] ||
  derive_encryption_secret.call("key_derivation_salt")
