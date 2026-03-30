# frozen_string_literal: true

class Analytics::SiteLocator
  class << self
    def from_record(record)
      return if record.blank?

      site = record.try(:analytics_site)
      return site if site.is_a?(Analytics::Site)

      from_id(record.try(:analytics_site_id))
    end

    def from_id(id)
      return if id.blank?

      Analytics::Site.find_by(id: id)
    end

    def from_public_id(public_id)
      return if public_id.blank?

      Analytics::Site.find_by(public_id: public_id.to_s)
    end
  end
end
