# frozen_string_literal: true

module Analytics::SqlExpression
  class << self
    def lower_matches(expression, pattern)
      Arel::Nodes::NamedFunction.new("LOWER", [ arel_expression(expression) ]).matches(pattern)
    end

    def in_list(expression, values)
      Arel::Nodes::Grouping.new(arel_expression(expression)).in(Array(values))
    end

    private
      def arel_expression(expression)
        Arel.sql(expression)
      end
  end
end
