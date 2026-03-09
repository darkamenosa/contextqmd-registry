# frozen_string_literal: true

# Attach identity and account context to all error reports.
# Works with any Rails.error subscriber (Sentry, Honeybadger, etc.)
Rails.error.add_middleware ->(error, context:, **) do
  context.merge(
    identity_id: Current.identity&.id,
    account_id: Current.account&.external_account_id
  )
end
