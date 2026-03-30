# frozen_string_literal: true

require "test_helper"

class Analytics::StorageTest < ActiveSupport::TestCase
  class StubQuery
    class Postgres
    end
  end

  test "defaults to postgres adapter" do
    with_analytics_storage(nil) do
      assert_equal "postgres", Analytics::Storage.current
      assert_equal Analytics::StorageTest::StubQuery::Postgres,
        Analytics::Storage.adapter_for(Analytics::StorageTest::StubQuery)
    end
  end

  test "raises for unsupported adapters" do
    with_analytics_storage("clickhouse") do
      error = assert_raises(NotImplementedError) do
        Analytics::Storage.adapter_for(Analytics::StorageTest::StubQuery)
      end

      assert_match "Unsupported analytics storage adapter: clickhouse", error.message
    end
  end

  test "raises when the query does not define the selected adapter" do
    with_analytics_storage(nil) do
      error = assert_raises(NotImplementedError) do
        Analytics::Storage.adapter_for(Class.new)
      end

      assert_match "does not define Postgres", error.message
    end
  end

  private
    def with_analytics_storage(value)
      previous = Analytics::Configuration.config.storage
      Analytics::Configuration.config.storage = value
      yield
    ensure
      Analytics::Configuration.config.storage = previous
    end
end
