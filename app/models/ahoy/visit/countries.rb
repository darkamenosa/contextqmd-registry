# frozen_string_literal: true

module Ahoy::Visit::Countries
  extend ActiveSupport::Concern

  included do
    before_validation :normalize_country_attributes
  end

  class_methods do
    def normalize_country_code(value)
      Analytics::Country::Parser.alpha2(value)
    end

    def country_name(code)
      Analytics::Country::Label.name_for(code)
    end

    def matching_country_codes(query)
      Analytics::Country::Search.alpha2_codes(query)
    end
  end

  private
    def normalize_country_attributes
      resolved = Analytics::Country.resolve(country:, country_code:)
      self.country_code = resolved.code
      self.country = resolved.name
    end
end
