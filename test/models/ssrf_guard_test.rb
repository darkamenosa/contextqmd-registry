# frozen_string_literal: true

require "test_helper"

class SsrfGuardTest < ActiveSupport::TestCase
  test "rejects localhost" do
    assert_not SsrfGuard.safe_uri?(URI.parse("http://localhost/admin"))
  end

  test "rejects 127.0.0.1" do
    assert_not SsrfGuard.safe_uri?(URI.parse("http://127.0.0.1/secret"))
  end

  test "rejects 0.0.0.0" do
    assert_not SsrfGuard.safe_uri?(URI.parse("http://0.0.0.0:8080/api"))
  end

  test "rejects nil host" do
    uri = URI.parse("http:///path")
    assert_not SsrfGuard.safe_uri?(uri)
  end

  test "allows public hosts" do
    assert SsrfGuard.safe_uri?(URI.parse("https://github.com/rails/rails"))
  end

  test "allows unknown hosts that fail DNS resolution" do
    # Unresolvable hosts are allowed — they'll fail at connect time
    assert SsrfGuard.safe_uri?(URI.parse("https://definitely-not-a-real-host-xyz123.example"))
  end
end
