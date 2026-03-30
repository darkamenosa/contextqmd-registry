# frozen_string_literal: true

module Analytics
  class EventsController < Ahoy::BaseController
    skip_forgery_protection
    before_action { Analytics::BrowserIdentity.ensure!(request, cookies:) }
    after_action { Analytics::TrackerCorsHeaders.apply!(response.headers) }
    around_action do |controller, action|
      ::Analytics::Current.reset
      ::Current.set(request: controller.request) { action.call }
    ensure
      ::Analytics::Current.reset
    end

    def create
      events =
        if params[:name]
          [ request.params ]
        elsif params[:events]
          request.params[:events]
        else
          data =
            if params[:events_json]
              request.params[:events_json]
            else
              request.body.read
            end
          begin
            ActiveSupport::JSON.decode(data)
          rescue ActiveSupport::JSON.parse_error
            []
          end
        end

      max_events_per_request = Ahoy.max_events_per_request

      unless events.is_a?(Array) && events.first(max_events_per_request).all? { |value| value.is_a?(Hash) }
        logger.info "[analytics] invalid event payload"
        render plain: "Invalid parameters\n", status: :bad_request
        return
      end

      events.first(max_events_per_request).each do |event|
        next unless trackable_event?(event)

        time = Time.zone.parse(event["time"]) rescue nil
        time ||= Time.zone.at(event["time"].to_f) rescue nil

        options = {
          id: event["id"],
          time: time
        }
        ahoy.track event["name"], event["properties"], options
      end

      render json: {}
    end

    private
      def trackable_event?(event)
        path = tracked_path_for(event)
        return true if path.blank?

        ::Analytics::TrackingRules.trackable_path?(
          path,
          site: site_for_event(event),
          include_internal_defaults: true
        )
      end

      def site_for_event(event)
        website_id = event["website_id"].to_s.presence
        return ::Analytics::SiteLocator.from_public_id(website_id) if website_id.present?

        site_token = event["site_token"].to_s.presence
        if site_token.present?
          resolution = ::Analytics::TrackerSiteToken.verify(
            site_token,
            host: tracked_host_for(event) || request.host,
            path: tracked_path_for(event) || "/",
            environment: Rails.env
          )
          return resolution&.site if resolution.present?
        end

        ::Analytics::Current.site_or_default
      end

      def tracked_path_for(event)
        properties = event["properties"].to_h
        page = properties["page"].to_s.presence
        return page if page.present?

        tracked_url = properties["url"].to_s
        return nil if tracked_url.blank?

        URI.parse(tracked_url).path.presence
      rescue URI::InvalidURIError
        nil
      end

      def tracked_host_for(event)
        tracked_url = event.dig("properties", "url").to_s
        return nil if tracked_url.blank?

        URI.parse(tracked_url).host
      rescue URI::InvalidURIError
        nil
      end
  end
end
