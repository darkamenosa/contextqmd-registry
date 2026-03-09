# frozen_string_literal: true

module Admin
  module Settings
    class TeamsController < Admin::BaseController
      def show
        render inertia: "admin/settings/team/show"
      end
    end
  end
end
