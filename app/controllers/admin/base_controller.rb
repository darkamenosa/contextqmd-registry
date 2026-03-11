# frozen_string_literal: true

module Admin
  class BaseController < InertiaController
    include Pagy::Method
    include BlockSearchEngineIndexing
    disallow_account_scope
    before_action :ensure_staff

    private
  end
end
