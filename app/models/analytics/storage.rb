# frozen_string_literal: true

class Analytics::Storage
  class << self
    def current
      Analytics::Configuration.storage.to_s
    end

    def adapter_for(query_class)
      adapter_name = adapter_class_name

      if query_class.const_defined?(adapter_name, false)
        query_class.const_get(adapter_name, false)
      else
        raise NotImplementedError,
          "#{query_class.name} does not define #{adapter_name} for analytics storage #{current}"
      end
    end

    private
      def adapter_class_name
        case current
        when "postgres"
          :Postgres
        else
          raise NotImplementedError, "Unsupported analytics storage adapter: #{current}"
        end
      end
  end
end
