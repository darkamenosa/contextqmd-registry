# frozen_string_literal: true

module InertiaXsrfCookieOverride
  extend ActiveSupport::Concern

  private

    def sync_inertia_xsrf_cookie
      return unless protect_against_forgery?
      return if (request.get? || request.head?) && request.cookies["XSRF-TOKEN"].present?

      cookies["XSRF-TOKEN"] = form_authenticity_token
    end
end

ActiveSupport.on_load(:action_controller_base) do
  include InertiaXsrfCookieOverride

  inertia_xsrf_callback = _process_action_callbacks.find do |callback|
    filter = callback.filter

    callback.kind == :after &&
      filter.is_a?(Proc) &&
      filter.source_location == [
        Gem.loaded_specs.fetch("inertia_rails").full_gem_path + "/lib/inertia_rails/controller.rb",
        14
      ]
  end

  skip_callback(:process_action, :after, inertia_xsrf_callback.filter) if inertia_xsrf_callback
  after_action :sync_inertia_xsrf_cookie
end
