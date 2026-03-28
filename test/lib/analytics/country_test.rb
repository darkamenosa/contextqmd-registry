# frozen_string_literal: true

require "test_helper"

class Analytics::CountryTest < ActiveSupport::TestCase
  test "resolve canonicalizes country names and alpha3 codes to alpha2" do
    resolved_from_name = Analytics::Country.resolve(country: "United States")
    resolved_from_alpha3 = Analytics::Country.resolve(country_code: "USA")

    assert_equal "US", resolved_from_name.code
    assert_equal "United States", resolved_from_name.name
    assert_equal "US", resolved_from_alpha3.code
    assert_equal "United States", resolved_from_alpha3.name
  end

  test "search resolves partial display names to alpha2 codes" do
    matches = Analytics::Country::Search.alpha2_codes("united")

    assert_includes matches, "US"
    assert_includes matches, "AE"
    assert_includes matches, "GB"
  end

  test "parser resolves common aliases" do
    assert_equal "AE", Analytics::Country::Parser.alpha2("UAE")
    assert_equal "CD", Analytics::Country::Parser.alpha2("DR Congo")
    assert_equal "CI", Analytics::Country::Parser.alpha2("Cote d Ivoire")
    assert_equal "GB", Analytics::Country::Parser.alpha2("England")
  end

  test "search keeps ambiguous country text broad while preserving exact aliases" do
    assert_equal [ "AE" ], Analytics::Country::Search.alpha2_codes("UAE")
    assert_includes Analytics::Country::Search.alpha2_codes("Congo"), "CG"
    assert_includes Analytics::Country::Search.alpha2_codes("Congo"), "CD"
  end
end
