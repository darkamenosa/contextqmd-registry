# frozen_string_literal: true

class Analytics::TrackerSnippet
  SCRIPT_PATH = "/js/script.js".freeze
  EVENTS_PATH = "/ahoy/events".freeze
  EXTERNAL_EXPIRY = 180.days

  class << self
    def build(site:, request:)
      return nil if site.blank? || request.blank?

      public_origin = configured_public_origin(request)
      site_token = Analytics::TrackerSiteToken.generate(
        site: site,
        mode: "external",
        expires_in: EXTERNAL_EXPIRY
      )

      script_url = "#{public_origin}#{SCRIPT_PATH}"
      events_endpoint = "#{public_origin}#{EVENTS_PATH}"
      domain_hint = site.canonical_hostname

      {
        script_url: script_url,
        events_endpoint: events_endpoint,
        site_token: site_token,
        domain_hint: domain_hint,
        public_origin: public_origin,
        snippet_html: snippet_html(
          script_url: script_url,
          events_endpoint: events_endpoint,
          site_token: site_token,
          domain_hint: domain_hint
        )
      }
    end

    private
      def configured_public_origin(request)
        configured = Analytics::Configuration.public_base_url
        base = configured.presence || request.base_url
        base.sub(%r{/+\z}, "")
      end

      def snippet_html(script_url:, events_endpoint:, site_token:, domain_hint:)
        <<~HTML.strip
          <script
            defer
            src="#{ERB::Util.html_escape(script_url)}"
            data-site-token="#{ERB::Util.html_escape(site_token)}"
            data-domain="#{ERB::Util.html_escape(domain_hint)}"
            data-api="#{ERB::Util.html_escape(events_endpoint)}"
          ></script>
        HTML
      end
  end
end
