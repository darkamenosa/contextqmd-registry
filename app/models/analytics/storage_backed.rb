# frozen_string_literal: true

module Analytics::StorageBacked
  extend ActiveSupport::Concern

  class_methods do
    def adapter_class
      Analytics::Storage.adapter_for(self)
    end
  end

  private
    def adapter
      @adapter ||= self.class.adapter_class.new(**adapter_arguments)
    end

    def adapter_arguments
      raise NotImplementedError
    end
end
