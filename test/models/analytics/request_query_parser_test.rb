# frozen_string_literal: true

require "test_helper"

class Analytics::RequestQueryParserTest < ActiveSupport::TestCase
  FIXTURE_PATH = Rails.root.join("test/fixtures/analytics_query_contract_cases.json")

  test "shared backend query contract fixtures stay stable" do
    fixture_cases.each do |fixture|
      parsed = Analytics::RequestQueryParser.parse(
        query_string: fixture.fetch("search").sub(/\A\?/, ""),
        params: Rack::Utils.parse_nested_query(fixture.fetch("search").sub(/\A\?/, "")),
        allowed_periods: Admin::Analytics::BaseController::ALLOWED_PERIODS
      )

      expected = fixture.fetch("backend")
      expected.each do |key, value|
        actual = parsed[key.to_sym]
        actual = parsed[key] if actual.nil? && parsed.key?(key)

        if value.nil?
          assert_nil actual, "#{fixture.fetch("name")} expected #{key} to be nil"
        else
          assert_equal value, actual, "#{fixture.fetch("name")} expected #{key}"
        end
      end

      Array(fixture["backend_absent_keys"]).each do |key|
        refute parsed.key?(key), "#{fixture.fetch("name")} should not include #{key}"
        refute parsed.key?(key.to_sym), "#{fixture.fetch("name")} should not include #{key}"
      end
    end
  end

  private
    def fixture_cases
      @fixture_cases ||= JSON.parse(File.read(FIXTURE_PATH))
    end
end
