# frozen_string_literal: true

require "countries"
require_relative "country/parser"
require_relative "country/label"
require_relative "country/search"

module Analytics
  module Country
    Resolved = Struct.new(:code, :name, keyword_init: true)

    class << self
      def resolve(country: nil, country_code: nil)
        code = Parser.alpha2(country_code) || Parser.alpha2(country)

        Resolved.new(
          code: code,
          name: Label.name_for(code)
        )
      end
    end
  end
end
