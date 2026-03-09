# frozen_string_literal: true

class Current < ActiveSupport::CurrentAttributes
  attribute :identity, :user, :account
  attribute :http_method, :request_id, :user_agent, :ip_address, :referrer

  def identity=(identity)
    super
    if identity.present? && account.present?
      self.user = identity.users.active.find_by(account: account)
    else
      self.user = nil
    end
  end

  def with_account(value, &)
    with(account: value, &)
  end

  def without_account(&)
    with(account: nil, &)
  end
end
