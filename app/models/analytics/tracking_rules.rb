# frozen_string_literal: true

class Analytics::TrackingRules
  KEY = "tracking_rules"

  RuleSet = Data.define(:include_paths, :exclude_paths)

  class << self
    def configured(site: ::Analytics::Current.site_or_default)
      rule_set = load(site:)
      rule_set.include_paths.any? || rule_set.exclude_paths.any?
    end

    def load(site: ::Analytics::Current.site_or_default)
      raw = ::Analytics::Setting.get_json(KEY, fallback: {}, site:)
      normalize(raw)
    end

    def effective(site: ::Analytics::Current.site_or_default)
      rule_set = load(site:)
      RuleSet.new(
        include_paths: rule_set.include_paths,
        exclude_paths: dedupe_preserving_order(
          ::Analytics::InternalPaths.tracker_exclude_prefixes + rule_set.exclude_paths
        )
      )
    end

    def save!(include_paths:, exclude_paths:, site: ::Analytics::Current.site_or_default)
      payload = {
        include_paths: normalize_paths(include_paths),
        exclude_paths: normalize_paths(exclude_paths)
      }
      ::Analytics::Setting.set_json(KEY, payload, site:)
    end

    def trackable_path?(path, site: ::Analytics::Current.site_or_default, include_internal_defaults: true)
      normalized_path = normalize_actual_path(path)
      return true if normalized_path.blank?

      rule_set = include_internal_defaults ? effective(site:) : load(site:)
      return false if rule_set.exclude_paths.any? { |pattern| path_matches?(pattern, normalized_path) }
      return true if rule_set.include_paths.empty?

      rule_set.include_paths.any? { |pattern| path_matches?(pattern, normalized_path) }
    end

    def site_for_request(request)
      resolution = ::Analytics::TrackingSiteResolver.resolve(
        host: request.host,
        path: request.path,
        url: request.original_url
      )
      resolution&.site || ::Analytics::Current.site_or_default
    end

    private
      def normalize(raw)
        value = raw.is_a?(Hash) ? raw.with_indifferent_access : {}
        RuleSet.new(
          include_paths: normalize_paths(value[:include_paths]),
          exclude_paths: normalize_paths(value[:exclude_paths])
        )
      end

      def normalize_paths(values)
        dedupe_preserving_order(Array(values).filter_map do |value|
          normalize_rule(value)
        end)
      end

      def dedupe_preserving_order(values)
        seen = {}
        values.each_with_object([]) do |value, list|
          next if seen[value]

          seen[value] = true
          list << value
        end
      end

      def normalize_rule(value)
        raw = value.to_s.strip
        return nil if raw.blank?

        normalized = raw.start_with?("/") ? raw : "/#{raw}"
        normalized = normalized.gsub(%r{/+}, "/")
        normalized.presence
      end

      def normalize_actual_path(value)
        raw = value.to_s.strip
        return nil if raw.blank?

        normalized = begin
          uri = URI.parse(raw)
          uri.path.presence || raw
        rescue URI::InvalidURIError
          raw
        end

        normalized = "/#{normalized}" unless normalized.start_with?("/")
        normalized.gsub(%r{/+}, "/")
      end

      def path_matches?(wildcard_path, actual_path)
        wc = wildcard_path.to_s.strip
        return false if wc.blank? || actual_path.blank?

        pattern =
          "^" +
          Regexp.escape(wc)
            .gsub('\*\*', ".*")
            .gsub('\*', "[^/]*") +
          "/?$"

        Regexp.new(pattern).match?(actual_path)
      rescue RegexpError
        false
      end
  end
end
