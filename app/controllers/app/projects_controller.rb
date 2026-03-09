# frozen_string_literal: true

module App
  class ProjectsController < BaseController
    def index
      render inertia: "app/projects/index"
    end
  end
end
