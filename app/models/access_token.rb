# frozen_string_literal: true

# Personal access tokens for API authentication (fizzy pattern).
# Token is shown once at creation — only the SHA-256 digest is stored.
class AccessToken < ApplicationRecord
  belongs_to :identity

  enum :permission, { read: "read", write: "write" }, default: :read

  scope :active, -> { where(expires_at: [ nil, Time.current.. ]) }

  def self.generate(identity:, name:, permission: :read, expires_at: nil)
    token = SecureRandom.urlsafe_base64(32)
    access_token = create!(
      identity: identity,
      name: name,
      permission: permission,
      token_digest: digest(token),
      token_prefix: token[0, 8],
      expires_at: expires_at
    )
    [ access_token, token ]
  end

  def self.authenticate(token)
    return nil unless token.present?

    access_token = find_by(token_digest: digest(token))
    return nil unless access_token&.active?

    [ access_token.identity, access_token ]
  end

  def allows?(method)
    method.in?(%w[ GET HEAD ]) || write?
  end

  def active?
    expires_at.nil? || expires_at > Time.current
  end

  def revoke
    destroy
  end

  def self.digest(token)
    Digest::SHA256.hexdigest(token)
  end
end
