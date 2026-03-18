# frozen_string_literal: true

module SeoHelper
  extend ActiveSupport::Concern

  private

    def canonical_url(path: request.path, allowed_params: [])
      base = "https://#{canonical_host}#{path}"
      query = allowed_params.filter_map { |key|
        value = params[key]
        "#{key}=#{CGI.escape(value.to_s)}" if value.present?
      }
      query.any? ? "#{base}?#{query.join("&")}" : base
    end

    def canonical_host
      ENV.fetch("APP_HOST", "contextqmd.com")
    end

    def breadcrumb_json_ld(items)
      {
        "@context": "https://schema.org",
        "@type": "BreadcrumbList",
        itemListElement: items.each_with_index.map { |item, i|
          {
            "@type": "ListItem",
            position: i + 1,
            name: item[:name],
            item: item[:url]
          }
        }
      }
    end

    def seo_props(title: nil, description: nil, url: nil, type: nil, noindex: nil, image: nil)
      props = {}
      props[:title] = title if title
      props[:description] = description if description
      props[:url] = url || canonical_url
      props[:type] = type if type
      props[:noindex] = noindex if noindex
      props[:image] = image if image
      props
    end
end
