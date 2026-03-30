# frozen_string_literal: true

module Analytics::Scope
  class << self
    def apply(scope, site: ::Analytics::Current.site_or_default, column: :analytics_site_id)
      site_id = extract_site_id(site)
      return scope if site_id.blank?

      scope.where(column => site_id)
    end

    private
      def extract_site_id(site)
        case site
        when Analytics::Site
          site.id
        else
          site.presence
        end
      end
  end
end
