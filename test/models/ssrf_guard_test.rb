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

  test "rejects unresolvable hosts (fail closed)" do
    assert_not SsrfGuard.safe_uri?(URI.parse("https://definitely-not-a-real-host-xyz123.example"))
  end

  test "rejects decimal IP for loopback (2130706433)" do
    assert_not SsrfGuard.safe_uri?(URI.parse("http://2130706433/secret"))
  end

  test "rejects hex IP for loopback (0x7f000001)" do
    assert_not SsrfGuard.safe_uri?(URI.parse("http://0x7f000001/secret"))
  end

  test "rejects shorthand loopback (127.1)" do
    assert_not SsrfGuard.safe_uri?(URI.parse("http://127.1/secret"))
  end

  test "rejects IPv6 loopback" do
    assert_not SsrfGuard.safe_uri?(URI.parse("http://[::1]/secret"))
  end

  test "rejects IPv4-mapped loopback (::ffff:127.0.0.1)" do
    assert_not SsrfGuard.safe_uri?(URI.parse("http://[::ffff:127.0.0.1]/secret"))
  end

  test "rejects link-local IPv6 (fe80::1)" do
    assert_not SsrfGuard.safe_uri?(URI.parse("http://[fe80::1]/secret"))
  end

  test "rejects RFC1918 10.x" do
    assert_not SsrfGuard.safe_uri?(URI.parse("http://10.0.0.1/internal"))
  end

  test "rejects RFC1918 192.168.x" do
    assert_not SsrfGuard.safe_uri?(URI.parse("http://192.168.1.1/admin"))
  end

  test "private_ip? helper" do
    assert SsrfGuard.private_ip?("127.0.0.1")
    assert SsrfGuard.private_ip?("10.0.0.1")
    assert SsrfGuard.private_ip?("::1")
    assert SsrfGuard.private_ip?("fe80::1")
    assert SsrfGuard.private_ip?("::ffff:127.0.0.1")
    assert_not SsrfGuard.private_ip?("8.8.8.8")
    assert_not SsrfGuard.private_ip?("2607:f8b0:4004:800::200e")
  end
end
