ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

Dir[Rails.root.join("test/support/**/*.rb")].each { |f| require f }

module ActiveSupport
  class TestCase
    include TenantTestHelper
    teardown { Current.reset }

    parallelize(workers: :number_of_processors)
  end
end
