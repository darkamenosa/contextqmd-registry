# frozen_string_literal: true

require "test_helper"

class SourcePolicyTest < ActiveSupport::TestCase
  fixtures :accounts, :libraries, :source_policies

  test "valid source policy" do
    library = Library.new(
      account: accounts(:personal),
      namespace: "test-org",
      name: "test-lib",
      display_name: "Test Lib"
    )
    library.save!

    policy = SourcePolicy.new(
      library: library,
      license_status: "verified",
      mirror_allowed: true
    )
    assert policy.valid?
  end

  test "requires valid license_status" do
    policy = SourcePolicy.new(library: libraries(:nextjs), license_status: "unknown")
    assert_not policy.valid?
    assert policy.errors[:license_status].present?
  end

  test "license_status must be one of verified, unclear, custom" do
    %w[verified unclear custom].each do |status|
      library = Library.new(
        account: accounts(:personal),
        namespace: "test-org",
        name: "test-#{status}",
        display_name: "Test #{status}"
      )
      library.save!

      policy = SourcePolicy.new(library: library, license_status: status)
      assert policy.valid?, "Expected license_status '#{status}' to be valid"
    end
  end

  test "mirror_safe? returns true when verified and mirror_allowed" do
    policy = source_policies(:nextjs_policy)
    policy.license_status = "verified"
    policy.mirror_allowed = true
    assert policy.mirror_safe?
  end

  test "mirror_safe? returns false when not verified" do
    policy = source_policies(:nextjs_policy)
    policy.license_status = "unclear"
    policy.mirror_allowed = true
    assert_not policy.mirror_safe?
  end

  test "mirror_safe? returns false when mirror not allowed" do
    policy = source_policies(:nextjs_policy)
    policy.license_status = "verified"
    policy.mirror_allowed = false
    assert_not policy.mirror_safe?
  end

  test "belongs to library" do
    policy = source_policies(:nextjs_policy)
    assert_equal libraries(:nextjs), policy.library
  end
end
