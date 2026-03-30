# frozen_string_literal: true

module Analytics
  module AhoyServerOwnedIdentity
    private
      def visit_token_helper
        return super if Ahoy.cookies?

        @visit_token_helper ||= begin
          if Analytics::VisitBoundary.force_new_visit?(request)
            generate_id unless Ahoy.api_only
          else
            super()
          end
        end
      end

      def existing_visit_token
        return super if Ahoy.cookies?

        nil
      end

      def existing_visitor_token
        return super if Ahoy.cookies?

        nil
      end

      def visitor_token_helper
        return super if Ahoy.cookies?

        @visitor_token_helper ||= begin
          token = Analytics::AnonymousIdentity.current(request)
          token ||= generate_id unless Ahoy.api_only
          token
        end
      end
  end
end
