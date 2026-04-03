ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "fileutils"

Dir[Rails.root.join("test/support/**/*.rb")].each { |f| require f }

if defined?(ActiveJob::QueueAdapters::TestAdapter) &&
    defined?(ActiveJob::QueueAdapters::AsyncExt) &&
    !(ActiveJob::QueueAdapters::TestAdapter < ActiveJob::QueueAdapters::AsyncExt)
  ActiveJob::QueueAdapters::TestAdapter.include ActiveJob::QueueAdapters::AsyncExt
end

module ActiveSupport
  class TestCase
    include TenantTestHelper

    def with_stubbed_singleton_method(object, method_name, replacement = nil, &block)
      singleton = object.singleton_class
      method_defined = object.respond_to?(method_name, true)
      visibility =
        if singleton.private_method_defined?(method_name)
          :private
        elsif singleton.protected_method_defined?(method_name)
          :protected
        else
          :public
        end
      original_method = object.method(method_name) if method_defined

      singleton.define_method(method_name) do |*args, **kwargs, &method_block|
        if replacement.respond_to?(:call)
          replacement.call(*args, **kwargs, &method_block)
        else
          replacement
        end
      end
      singleton.send(visibility, method_name) unless visibility == :public

      yield
    ensure
      singleton.send(:remove_method, method_name) rescue nil
      if method_defined && original_method
        singleton.define_method(method_name, original_method)
        singleton.send(visibility, method_name) unless visibility == :public
      end
    end

    teardown do
      Current.reset
      ::Analytics::Current.reset if defined?(::Analytics::Current)
    end

    parallelize(workers: :number_of_processors)

    parallelize_setup do |worker|
      storage_root = Rails.root.join("tmp/storage-#{worker}")
      FileUtils.rm_rf(storage_root)
      FileUtils.mkdir_p(storage_root)

      ActiveStorage::Blob.services.fetch(:test).root = storage_root
      ActiveStorage::Blob.service.root = storage_root if ActiveStorage::Blob.service.respond_to?(:root=)
    end

    setup do
      # Ensure the system account + system user exist (mirrors db/seeds.rb).
      system_acct = Account.find_or_create_by!(name: Account::SYSTEM_ACCOUNT_NAME) { |a| a.personal = false }
      system_acct.users.find_or_create_by!(role: :system) { |u| u.name = "System" }
    end

    parallelize_teardown do |worker|
      FileUtils.rm_rf(Rails.root.join("tmp/storage-#{worker}"))
    end
  end
end
