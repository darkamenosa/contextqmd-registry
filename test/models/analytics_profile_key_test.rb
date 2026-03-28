# frozen_string_literal: true

require "test_helper"

class AnalyticsProfileKeyTest < ActiveSupport::TestCase
  test "normalize_strong_keys accepts a hash of keys" do
    normalized_keys = AnalyticsProfileKey.normalize_strong_keys(
      identity_id: 123,
      email_hash: "abc"
    )

    assert_equal(
      [
        { kind: "identity_id", value: "123" },
        { kind: "email_hash", value: "abc" }
      ],
      normalized_keys
    )
  end

  test "normalize_strong_keys accepts an array of normalized keys" do
    normalized_keys = AnalyticsProfileKey.normalize_strong_keys(
      [
        { kind: :identity_id, value: 123 },
        { kind: "email_hash", value: "abc" }
      ]
    )

    assert_equal(
      [
        { kind: "identity_id", value: "123" },
        { kind: "email_hash", value: "abc" }
      ],
      normalized_keys
    )
  end
end
