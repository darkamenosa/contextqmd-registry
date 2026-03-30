# frozen_string_literal: true

class ::Analytics::Current < ActiveSupport::CurrentAttributes
  attribute :site, :site_boundary

  class << self
    def site_or_default
      site || ::Analytics::Site.sole_active
    end

    def site_boundary_or_default
      site_boundary || site_or_default&.boundaries&.find_by(primary: true)
    end
  end
end
