# frozen_string_literal: true

class Analytics::TrackerSnippet
  EXTERNAL_EXPIRY = 180.days

  class << self
    def build(site:, request:)
      return nil if site.blank? || request.blank?

      public_origin = configured_public_origin(request)
      script_url = "#{public_origin}#{Analytics::TrackerLoader.script_path}"
      domain_hint = site.canonical_hostname

      {
        script_url: script_url,
        website_id: site.public_id,
        domain_hint: domain_hint,
        snippet_html: snippet_html(
          script_url: script_url,
          website_id: site.public_id
        )
      }
    end

    private
      def configured_public_origin(request)
        configured = Analytics::Configuration.public_base_url
        base = configured.presence || request.base_url
        base.sub(%r{/+\z}, "")
      end

      def snippet_html(script_url:, website_id:)
        <<~HTML.strip
          <script
            defer
            src="#{ERB::Util.html_escape(script_url)}"
            data-website-id="#{ERB::Util.html_escape(website_id)}"
          ></script>
        HTML
      end
  end
end
