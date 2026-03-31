# frozen_string_literal: true

require_relative "../client_ip"
require_relative "country"
require_relative "anonymous_identity"
require_relative "browser_identity"
require_relative "visit_boundary"

class Analytics::AhoyStore < Ahoy::DatabaseStore
  class InvalidTrackedSiteClaim < StandardError; end

  def visit_columns
    super + %i[hostname screen_size browser_version browser_id country_code analytics_site_id analytics_site_boundary_id]
  end

  def visit
    unless defined?(@visit)
      if ahoy.send(:existing_visit_token) || ahoy.instance_variable_get(:@visit_token)
        @visit = visit_model.where(visit_token: ahoy.visit_token).take if ahoy.visit_token
      elsif !Ahoy.cookies?
        @visit = if force_new_visit_boundary?
          nil
        else
          visit_model
            .where(visitor_token: anonymous_visitor_tokens)
            .where(started_at: Ahoy.visit_duration.ago..)
            .order(started_at: :desc)
            .first
        end
      else
        @visit = nil
      end
    end

    @visit
  end

  def track_visit(data)
    attrs = normalize_visit_attrs(data)

    visit = super(attrs) || visit_for_token(attrs[:visit_token])
    Analytics::VisitBoundary.consume_force_new_visit!(Current.request) if Current.request
    resolve_analytics_profile(visit, occurred_at: visit&.started_at)
    Analytics::LiveState.broadcast_later(site: Analytics::SiteLocator.from_record(visit))
    visit
  rescue InvalidTrackedSiteClaim
    nil
  end

  def track_event(data)
    data = data.with_indifferent_access

    return nil if data[:name].to_s == "engagement" && visit.nil?

    resolved_visit = visit || create_visit_from_event(data)
    unless resolved_visit
      Ahoy.log "Event excluded since visit not created: #{data[:visit_token]}"
      return nil
    end

    event = event_model.new(slice_data(event_model, data))
    event.visit = resolved_visit
    event.analytics_site_id ||= resolved_visit.analytics_site_id if event.respond_to?(:analytics_site_id)
    event.analytics_site_boundary_id ||= resolved_visit.analytics_site_boundary_id if event.respond_to?(:analytics_site_boundary_id)
    event.time = resolved_visit.started_at if event.time < resolved_visit.started_at

    begin
      event.save!
    rescue => e
      raise e unless unique_exception?(e)
      return nil
    end

    sync_event_site_scope!(event, resolved_visit)
    resolve_analytics_profile(resolved_visit, occurred_at: event.time) if resolved_visit.should_resolve_profile_for_event?(strong_keys: strong_keys_for(resolved_visit))
    Analytics::LiveState.broadcast_later(
      site: Analytics::SiteLocator.from_record(resolved_visit) || Analytics::SiteLocator.from_record(event)
    )
    event
  rescue InvalidTrackedSiteClaim
    nil
  end

  def authenticate(data)
    super

    resolved_visit = visit
    resolve_analytics_profile(resolved_visit, occurred_at: Time.current)
    Analytics::LiveState.broadcast_later(site: Analytics::SiteLocator.from_record(resolved_visit))
  end

  private
    def normalize_visit_attrs(data)
      attrs = Analytics::VisitAttributes.normalize(data, request: Current.request)
      Analytics::TrackedSiteAttributes.merge!(attrs, request: Current.request)

      attrs
    rescue InvalidTrackedSiteClaim
      raise
    rescue StandardError
      attrs
    end

    def create_visit_from_event(data)
      event_data = data.with_indifferent_access
      props = event_data[:properties].to_h.with_indifferent_access
      visit_data = {
        started_at: event_data[:time],
        landing_page: props[:url].presence,
        referrer: props[:referrer].presence,
        screen_size: props[:screen_size].presence,
        path: props[:page].presence,
        site_token: event_data[:site_token].presence,
        website_id: event_data[:website_id].presence
      }.compact

      track_visit(visit_data)
    end

    def visit_for_token(token)
      return nil if token.blank?

      ::Ahoy::Visit.find_by(visit_token: token)
    end

    def anonymous_visitor_tokens
      tokens = Analytics::AnonymousIdentity.tokens(request)
      tokens.presence || [ ahoy.visitor_token ].compact
    end

    def sync_event_site_scope!(event, visit)
      return unless event.respond_to?(:analytics_site_id)
      return if event.analytics_site_id.present? && event.analytics_site_boundary_id.present?

      updates = {}
      updates[:analytics_site_id] = visit.analytics_site_id if event.analytics_site_id.blank? && visit.analytics_site_id.present?
      if event.analytics_site_boundary_id.blank? && visit.analytics_site_boundary_id.present?
        updates[:analytics_site_boundary_id] = visit.analytics_site_boundary_id
      end
      return if updates.empty?

      event.update_columns(updates)
      event.assign_attributes(updates)
    rescue StandardError
      nil
    end

    def resolve_analytics_profile(visit, occurred_at:)
      return if visit.blank?

      visit.resolve_profile_later(
        browser_id: browser_id_for(visit),
        strong_keys: strong_keys_for(visit),
        occurred_at: occurred_at,
        identity_snapshot: visit.analytics_identity_snapshot(current_identity: Current.identity)
      )
    rescue StandardError
      nil
    end

    def browser_id_for(visit)
      browser_id = Analytics::BrowserIdentity.current(request)
      return browser_id if browser_id.present?

      visit.browser_id if visit.respond_to?(:has_attribute?) && visit.has_attribute?(:browser_id)
    end

    def strong_keys_for(visit)
      visit.analytics_strong_keys
    end

    def force_new_visit_boundary?
      request.present? && Analytics::VisitBoundary.force_new_visit?(request)
    end
end
