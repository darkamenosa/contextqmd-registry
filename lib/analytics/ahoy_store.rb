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
        @visit = Analytics::FactStore.visit_by_token(token: ahoy.visit_token, site: nil) if ahoy.visit_token
      elsif !Ahoy.cookies?
        @visit = if force_new_visit_boundary?
          nil
        else
          Analytics::FactStore.latest_visit_for_visitor_tokens(
            visitor_tokens: anonymous_visitor_tokens,
            started_after: Ahoy.visit_duration.ago,
            site: nil
          )
        end
      else
        @visit = nil
      end
    end

    @visit
  end

  def track_visit(data)
    attrs = normalize_visit_attrs(data)

    visit = Analytics::FactStore.append_visit(data: attrs).record || visit_for_token(attrs[:visit_token])
    @visit = visit
    Analytics::VisitBoundary.consume_force_new_visit!(Current.request) if Current.request
    resolve_analytics_profile(visit, occurred_at: visit&.started_at)
    Analytics::SiteVisitHourlyRollup.refresh_later(
      site: Analytics::SiteLocator.from_record(visit),
      bucket_start: visit&.started_at
    )
    Analytics::SiteSourceHourlyVisitorRollup.refresh_later(
      site: Analytics::SiteLocator.from_record(visit),
      bucket_start: visit&.started_at
    )
    Analytics::SiteLocationHourlyVisitorRollup.refresh_later(
      site: Analytics::SiteLocator.from_record(visit),
      bucket_start: visit&.started_at
    )
    Analytics::VisitSummary.refresh_later(visit:)
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

    append_result = Analytics::FactStore.append_event(data:, visit: resolved_visit)
    event = append_result.record
    return event unless append_result.inserted?

    Analytics::VisitSummary.refresh_later(visit: resolved_visit)
    Analytics::SiteEventHourlyRollup.refresh_later(
      site: Analytics::SiteLocator.from_record(resolved_visit) || Analytics::SiteLocator.from_record(event),
      bucket_start: event.time
    )
    if event.name.in?(%w[pageview engagement])
      Analytics::VisitPageEngagement.refresh_later(visit: resolved_visit)
    end
    if event.name == "pageview"
      Analytics::SitePageHourlyRollup.refresh_later(
        site: Analytics::SiteLocator.from_record(resolved_visit) || Analytics::SiteLocator.from_record(event),
        bucket_start: event.time
      )
    end
    resolved_visit.project_later
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
        user_id: user&.id,
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

      Analytics::FactStore.visit_by_token(token: token, site: nil)
    end

    def resolve_analytics_profile(visit, occurred_at:)
      return if visit.blank?

      visit.resolve_profile_later(
        browser_id: browser_id_for(visit),
        strong_keys: strong_keys_for(visit),
        occurred_at: occurred_at
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

    def anonymous_visitor_tokens
      tokens = Analytics::AnonymousIdentity.tokens(request)
      tokens.presence || [ ahoy.visitor_token ].compact
    end

    def force_new_visit_boundary?
      request.present? && Analytics::VisitBoundary.force_new_visit?(request)
    end
end
