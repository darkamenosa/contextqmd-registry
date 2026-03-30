# frozen_string_literal: true

module Analytics
  module HostIntegration
    extend ActiveSupport::Concern

    include ::ServerSidePageviewTracking

    included do
      around_action :with_analytics_current
    end

    private
      def with_analytics_current
        ::Analytics::Current.reset
        yield
      ensure
        ::Analytics::Current.reset
      end
  end
end
