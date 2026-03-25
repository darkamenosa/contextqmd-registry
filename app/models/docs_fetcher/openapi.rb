# frozen_string_literal: true

require "json"
require "yaml"

module DocsFetcher
  # Fetches and parses OpenAPI/Swagger specifications into documentation pages.
  # Supports JSON and YAML formats, OpenAPI 3.x and Swagger 2.0.
  #
  # Strategy:
  # 1. Fetch the spec file from URL
  # 2. Parse as JSON or YAML
  # 3. Generate one page per API path (grouped by tag when available)
  # 4. Generate overview page from info section
  # 5. Generate schema pages for reusable components
  class Openapi
    include HttpFetching

    MAX_SIZE = 10_000_000 # 10MB

    def probe_version(url)
      uri = URI.parse(url.strip)
      raw = http_get(uri)
      return nil if raw.blank?

      spec = parse_spec(raw)
      return nil unless spec.is_a?(Hash)

      version = extract_metadata(spec, uri)[:version]
      return nil if version.blank?

      {
        version: version,
        crawl_url: url
      }
    end

    def fetch(crawl_request, on_progress: nil)
      url = crawl_request.url
      uri = URI.parse(url.strip)

      on_progress&.call("Fetching OpenAPI spec")
      raw = http_get(uri)
      raise DocsFetcher::TransientFetchError, "Failed to fetch #{url}" unless raw

      spec = parse_spec(raw)
      raise DocsFetcher::PermanentFetchError, "Invalid OpenAPI spec at #{url}" unless spec.is_a?(Hash)

      metadata = extract_metadata(spec, uri)
      on_progress&.call("Generating API documentation pages")
      pages = build_pages(spec, url)
      raise DocsFetcher::PermanentFetchError, "No API documentation found in #{url}" if pages.empty?

      CrawlResult.new(
        slug: metadata[:slug],
        namespace: metadata[:namespace],
        name: metadata[:name],
        display_name: metadata[:display_name],
        homepage_url: metadata[:homepage_url] || url,
        aliases: metadata[:aliases],
        version: metadata[:version],
        pages: pages
      )
    end

    private

      def parse_spec(raw)
        JSON.parse(raw)
      rescue JSON::ParserError
        YAML.safe_load(
          raw,
          permitted_classes: [ Date, Time ],
          permitted_symbols: [],
          aliases: false
        )
      rescue Psych::BadAlias, Psych::DisallowedClass, Psych::SyntaxError
        nil
      end

      def extract_metadata(spec, uri)
        info = spec["info"] || {}
        title = info["title"]
        identity = LibraryIdentity.from_openapi(uri: uri, title: title)

        {
          slug: identity[:slug],
          namespace: identity[:namespace],
          name: identity[:name],
          display_name: identity[:display_name],
          homepage_url: info["termsOfService"] || spec.dig("externalDocs", "url"),
          version: info["version"],
          aliases: identity[:aliases]
        }
      end

      def build_pages(spec, base_url)
        pages = []
        pages << overview_page(spec, base_url)
        pages.concat(endpoint_pages(spec, base_url))
        pages.concat(schema_pages(spec, base_url))
        pages.compact
      end

      # --- Overview page ---

      def overview_page(spec, base_url)
        info = spec["info"] || {}
        content = +""
        content << "# #{info['title'] || 'API Documentation'}\n\n"
        content << "#{info['description']}\n\n" if info["description"]
        content << "**Version:** #{info['version']}\n\n" if info["version"]

        if (servers = spec["servers"])
          content << "## Servers\n\n"
          servers.each do |s|
            content << "- `#{s['url']}` — #{s['description'] || 'Default'}\n"
          end
          content << "\n"
        elsif spec["host"]
          scheme = (spec["schemes"] || [ "https" ]).first
          content << "**Base URL:** `#{scheme}://#{spec['host']}#{spec['basePath']}`\n\n"
        end

        if (security_defs = spec.dig("components", "securitySchemes") || spec["securityDefinitions"])
          content << "## Authentication\n\n"
          security_defs.each do |name, scheme|
            content << "- **#{name}** — #{scheme['type']}"
            content << " (#{scheme['scheme']})" if scheme["scheme"]
            content << ": #{scheme['description']}" if scheme["description"]
            content << "\n"
          end
          content << "\n"
        end

        {
          page_uid: "overview",
          path: "overview.md",
          title: info["title"] || "API Overview",
          url: base_url,
          content: content.strip,
          headings: extract_headings(content)
        }
      end

      # --- Endpoint pages (one per tag, or one per path) ---

      def endpoint_pages(spec, base_url)
        paths = spec["paths"] || {}
        return [] if paths.empty?

        # Group endpoints by tag
        by_tag = Hash.new { |h, k| h[k] = [] }

        paths.each do |path, methods|
          next unless methods.is_a?(Hash)

          methods.each do |method, operation|
            next unless %w[get post put patch delete options head].include?(method)
            next unless operation.is_a?(Hash)

            tags = operation["tags"] || [ "Untagged" ]
            tags.each do |tag|
              by_tag[tag] << { path: path, method: method.upcase, operation: operation }
            end
          end
        end

        by_tag.map do |tag, endpoints|
          content = +"# #{tag}\n\n"

          # Tag description from tags array
          tag_info = (spec["tags"] || []).find { |t| t["name"] == tag }
          content << "#{tag_info['description']}\n\n" if tag_info&.dig("description")

          endpoints.each do |ep|
            op = ep[:operation]
            content << "## #{ep[:method]} #{ep[:path]}\n\n"
            content << "#{op['summary']}\n\n" if op["summary"]
            content << "#{op['description']}\n\n" if op["description"] && op["description"] != op["summary"]

            # Parameters
            params = op["parameters"] || []
            if params.any?
              content << "### Parameters\n\n"
              params.each do |p|
                required = p["required"] ? " *(required)*" : ""
                content << "- `#{p['name']}` (#{p['in']}, #{p['schema']&.dig('type') || p['type'] || 'any'})#{required}"
                content << " — #{p['description']}" if p["description"]
                content << "\n"
              end
              content << "\n"
            end

            # Request body
            if (body = op["requestBody"])
              content << "### Request Body\n\n"
              content << "#{body['description']}\n\n" if body["description"]
              render_content_schemas(content, body["content"])
            end

            # Responses
            responses = op["responses"] || {}
            if responses.any?
              content << "### Responses\n\n"
              responses.each do |status, resp|
                content << "- **#{status}**: #{resp['description'] || 'No description'}\n"
                render_content_schemas(content, resp["content"], indent: "  ")
              end
              content << "\n"
            end
          end

          slug = slugify(tag)
          {
            page_uid: slug,
            path: "#{slug}.md",
            title: tag,
            url: "#{base_url}##{slug}",
            content: content.strip,
            headings: extract_headings(content)
          }
        end
      end

      # --- Schema pages ---

      def schema_pages(spec, base_url)
        schemas = spec.dig("components", "schemas") || spec["definitions"] || {}
        return [] if schemas.empty?

        content = +"# Data Models\n\n"

        schemas.each do |name, schema|
          content << "## #{name}\n\n"
          content << "#{schema['description']}\n\n" if schema["description"]

          properties = schema["properties"] || {}
          required_fields = schema["required"] || []

          if properties.any?
            content << "| Field | Type | Required | Description |\n"
            content << "|-------|------|----------|-------------|\n"
            properties.each do |field, prop|
              type = prop["type"] || prop["$ref"]&.split("/")&.last || "object"
              type = "#{type}[]" if prop["type"] == "array"
              req = required_fields.include?(field) ? "Yes" : "No"
              desc = (prop["description"] || "").gsub("\n", " ").truncate(100)
              content << "| `#{field}` | #{type} | #{req} | #{desc} |\n"
            end
            content << "\n"
          end

          # Enum values
          if schema["enum"]
            content << "**Allowed values:** #{schema['enum'].map { |v| "`#{v}`" }.join(', ')}\n\n"
          end
        end

        [ {
          page_uid: "schemas",
          path: "schemas.md",
          title: "Data Models",
          url: "#{base_url}#schemas",
          content: content.strip,
          headings: extract_headings(content)
        } ]
      end

      # --- Helpers ---

      def render_content_schemas(content, media_types, indent: "")
        return unless media_types.is_a?(Hash)

        media_types.each do |media_type, details|
          schema = details["schema"]
          next unless schema

          ref = schema["$ref"]
          type = schema["type"]

          if ref
            model = ref.split("/").last
            content << "#{indent}Schema: `#{model}`\n"
          elsif type
            content << "#{indent}Type: `#{type}`\n"
          end
        end
      end

      def extract_headings(content)
        content.scan(/^\#{2,4}\s+(.+)$/).flatten.map(&:strip)
      end

      def slugify(text)
        text.to_s
          .downcase
          .gsub(/[^a-z0-9\s-]/, "")
          .strip
          .gsub(/\s+/, "-")
          .gsub(/-{2,}/, "-")
          .delete_prefix("-")
          .delete_suffix("-")
          .presence || "api"
      end

      def http_get(uri, **options)
        super(
          uri,
          **options,
          raise_on_error: true,
          accept: "application/json, application/yaml, text/yaml, */*",
          user_agent: "ContextQMD-Registry/1.0",
          max_size: MAX_SIZE,
          oversize: :nil
        )
      end
  end
end
