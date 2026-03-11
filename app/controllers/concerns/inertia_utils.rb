# frozen_string_literal: true

require "active_support/concern"

# Inertia.js specific utilities for controllers.
module InertiaUtils
  extend ActiveSupport::Concern

  def inertia_errors(model, full_messages: true)
    {
      errors: model.errors.to_hash(full_messages).transform_values(&:to_sentence)
    }
  end

  def pagination_props(pagy)
    {
      page: pagy.page,
      per_page: pagy.limit,
      total: pagy.count,
      pages: pagy.last,
      from: pagy.from,
      to: pagy.to,
      has_previous: pagy.previous.present?,
      has_next: pagy.next.present?
    }
  end
end
