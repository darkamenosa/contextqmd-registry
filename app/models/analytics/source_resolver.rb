# frozen_string_literal: true

require "cgi"
require "ipaddr"
require "yaml"

module Analytics
  class SourceResolver
    DIRECT_LABEL = "Direct / None"

    Rule = Data.define(:id, :target, :type, :pattern, :label, :paid)
    Resolution = Data.define(
      :source_label,
      :source_kind,
      :source_channel,
      :source_favicon_domain,
      :source_paid,
      :source_rule_id,
      :source_rule_version,
      :source_match_strategy
    )

    class << self
      def resolve(referrer: nil, referring_domain: nil, utm_source: nil, utm_medium: nil, utm_campaign: nil, landing_page: nil, hostname: nil)
        tagged_source = utm_source.to_s.strip
        normalized_domain = normalize_host(referring_domain.presence || referrer)
        site_host = normalize_host(hostname.presence || host_from_url(landing_page))

        label = nil
        rule_id = nil
        paid = false
        match_strategy = nil

        if direct_alias?(tagged_source)
          label = DIRECT_LABEL
          rule_id = "direct:utm_source"
          match_strategy = "direct_alias"
        elsif tagged_source.present?
          if (rule = match_rule(:utm_source, tagged_source))
            label = rule.label
            rule_id = rule.id
            paid = rule.paid
            match_strategy = "utm_source_#{rule.type}"
          else
            label = canonical_label(tagged_source) || tagged_source
            rule_id = label == tagged_source ? "fallback:utm_source" : "label:utm_source"
            match_strategy = label == tagged_source ? "fallback_utm_source" : "label_lookup"
          end
        elsif normalized_domain.blank? || direct_domain?(normalized_domain, site_host)
          label = DIRECT_LABEL
          rule_id = "direct:referrer"
          match_strategy = "direct_referrer"
        elsif (rule = match_rule(:domain, normalized_domain))
          label = rule.label
          rule_id = rule.id
          paid = rule.paid
          match_strategy = "domain_#{rule.type}"
        else
          label = normalized_domain
          rule_id = "fallback:domain"
          match_strategy = "fallback_domain"
        end

        kind = kind_for(label)
        paid ||= paid_source?(tagged_source)
        channel = channel_for(
          label: label,
          kind: kind,
          paid: paid,
          utm_source: tagged_source,
          utm_medium: utm_medium,
          utm_campaign: utm_campaign,
          landing_page: landing_page
        )

        Resolution.new(
          source_label: label,
          source_kind: kind,
          source_channel: channel,
          source_favicon_domain: favicon_domain_for(label, fallback_domain: normalized_domain),
          source_paid: paid,
          source_rule_id: rule_id,
          source_rule_version: rule_version,
          source_match_strategy: match_strategy
        )
      end

      def canonical_label(value)
        return DIRECT_LABEL if direct_alias?(value)

        labels_by_normalized_key[normalize_key(value)]
      end

      def kind_for(label)
        canonical_label = canonical_label(label) || label.to_s.strip
        metadata = labels[canonical_label] || {}
        metadata.fetch("kind", canonical_label == DIRECT_LABEL ? "direct" : "referral")
      end

      def favicon_domain_for(label, fallback_domain: nil)
        canonical = canonical_label(label) || label.to_s.strip
        metadata = labels[canonical] || {}
        metadata["favicon_domain"].presence || fallback_domain.presence
      end

      def rule_version
        config.fetch("version", 1).to_i
      end

      def direct_alias?(value)
        direct_aliases.include?(value.to_s.strip.downcase)
      end

      def paid_source?(value)
        candidate = value.to_s.strip.downcase
        return false if candidate.empty?

        paid_aliases.include?(candidate)
      end

      def rules_for_label(label)
        canonical = canonical_label(label) || label.to_s.strip
        rules.select { |rule| rule.label == canonical }
      end

      def labels
        config.fetch("labels", {})
      end

      def reload!
        @config = nil
        @rules = nil
        @direct_aliases = nil
        @paid_aliases = nil
        @labels_by_normalized_key = nil
      end

      private
        def config
          @config ||= begin
            base = load_yaml(Rails.root.join("config/analytics/source_rules.yml"))
            local = load_yaml(Rails.root.join("config/analytics/source_rules.local.yml"))
            deep_merge(base, local)
          end
        end

        def load_yaml(path)
          return {} unless File.exist?(path)

          YAML.safe_load(
            File.read(path),
            permitted_classes: [],
            permitted_symbols: [],
            aliases: false
          ) || {}
        end

        def deep_merge(base, override)
          return base unless override.is_a?(Hash)

          base.merge(override) do |_key, left, right|
            if left.is_a?(Hash) && right.is_a?(Hash)
              deep_merge(left, right)
            elsif left.is_a?(Array) && right.is_a?(Array)
              left + right
            else
              right
            end
          end
        end

        def labels_by_normalized_key
          @labels_by_normalized_key ||= labels.each_with_object({}) do |(label, _metadata), memo|
            memo[normalize_key(label)] = label
          end
        end

        def rules
          @rules ||= Array(config["rules"]).filter_map do |entry|
            next unless entry.is_a?(Hash)

            pattern = case entry["type"]
            when "regex"
              Regexp.new(entry.fetch("pattern"), Regexp::IGNORECASE)
            else
              entry.fetch("pattern").to_s.downcase
            end

            Rule.new(
              id: entry.fetch("id"),
              target: entry.fetch("target").to_sym,
              type: entry.fetch("type").to_sym,
              pattern: pattern,
              label: entry.fetch("label"),
              paid: ActiveModel::Type::Boolean.new.cast(entry["paid"])
            )
          end.freeze
        end

        def direct_aliases
          @direct_aliases ||= Array(config["direct_aliases"]).map { |value| value.to_s.downcase }.to_set.freeze
        end

        def paid_aliases
          @paid_aliases ||= rules.select(&:paid).filter_map do |rule|
            next unless rule.target == :utm_source
            next unless rule.type == :exact

            rule.pattern
          end.to_set.freeze
        end

        def match_rule(target, value)
          candidate = target == :domain ? normalize_host(value) : value.to_s.strip.downcase
          return nil if candidate.blank?

          rules.find do |rule|
            next false unless rule.target == target

            case rule.type
            when :exact
              candidate == rule.pattern
            when :suffix
              candidate == rule.pattern || candidate.end_with?(".#{rule.pattern}")
            when :regex
              candidate.match?(rule.pattern)
            else
              false
            end
          end
        end

        def channel_for(label:, kind:, paid:, utm_source:, utm_medium:, utm_campaign:, landing_page:)
          source = label.to_s.downcase
          medium = utm_medium.to_s.downcase
          campaign = utm_campaign.to_s.downcase
          tagged_source = utm_source.to_s.downcase

          return "Cross-network" if campaign.include?("cross-network")
          return "Paid Shopping" if (kind == "shopping" || shopping_campaign?(campaign)) && paid_medium?(medium)
          return "Paid Search" if kind == "search" && (paid_medium?(medium) || paid || click_id_paid_search?(source, landing_page))
          return "Paid Social" if kind == "social" && (paid_medium?(medium) || paid)
          return "Paid Video" if kind == "video" && (paid_medium?(medium) || paid)
          return "Display" if %w[display banner expandable interstitial cpm].include?(medium)
          return "Paid Other" if paid_medium?(medium)
          return "Organic Shopping" if kind == "shopping" || shopping_campaign?(campaign)
          return "Organic Social" if kind == "social" || organic_social_medium?(medium)
          return "Organic Video" if kind == "video" || medium.include?("video")
          return "Organic Search" if kind == "search"
          return "Email" if kind == "email" || email_tag?(tagged_source) || email_tag?(medium)
          return "Affiliates" if medium == "affiliate"
          return "Audio" if medium == "audio"
          return "SMS" if tagged_source == "sms" || medium == "sms"
          return "Mobile Push Notifications" if mobile_push?(tagged_source, medium)
          return "Developer" if kind == "developer"
          return "Direct" if label == DIRECT_LABEL && medium.blank? && tagged_source.blank?
          return "Email" if email_tag?(medium)
          return "Direct" if label == DIRECT_LABEL

          "Referral"
        end

        def shopping_campaign?(campaign)
          campaign.match?(/(^|[^a-df-z])shop|shopping/)
        end

        def paid_medium?(medium)
          medium.match?(/(^.*cp.*|ppc|retargeting|paid.*)$/)
        end

        def organic_social_medium?(medium)
          medium.in?([ "social", "social-network", "social-media", "sm", "social network", "social media" ])
        end

        def email_tag?(value)
          candidate = value.to_s.downcase
          return false if candidate.empty?

          email_tags.any? { |tag| candidate.include?(tag) }
        end

        def email_tags
          @email_tags ||= Array(config["email_tags"]).map(&:downcase).freeze
        end

        def mobile_push?(tagged_source, medium)
          medium.end_with?("push") || medium.include?("mobile") || medium.include?("notification") || tagged_source == "firebase"
        end

        def click_id_paid_search?(label, landing_page)
          return false if landing_page.blank?

          query = begin
            URI.parse(landing_page.to_s).query.to_s
          rescue URI::InvalidURIError
            landing_page.to_s
          end

          (label.include?("google") && query.include?("gclid=")) || (label.include?("bing") && query.include?("msclkid="))
        end

        def direct_domain?(domain, site_host)
          return true if domain.blank? || local_host?(domain)
          return false if site_host.blank?

          sanitize_host(domain) == sanitize_host(site_host)
        end

        def normalize_host(value)
          candidate = CGI.unescape(value.to_s).strip
          return nil if candidate.blank?

          if candidate.start_with?("android-app://")
            return candidate.downcase
          end

          parseable = candidate
          parseable = "https:#{parseable}" if parseable.start_with?("//")
          parseable = "https://#{parseable}" if !parseable.match?(/\A[a-z][a-z0-9+.-]*:/i) && parseable.include?(".")
          uri = URI.parse(parseable)
          host = uri.host.presence || candidate.split("/", 2).first
          sanitize_host(host)
        rescue URI::InvalidURIError
          sanitize_host(candidate.split("/", 2).first)
        end

        def sanitize_host(value)
          value.to_s.downcase.sub(/\Awww\./, "")
        end

        def host_from_url(value)
          return nil if value.blank?

          sanitize_host(URI.parse(value.to_s).host)
        rescue URI::InvalidURIError
          nil
        end

        def local_host?(value)
          candidate = value.to_s.downcase
          return true if candidate == "localhost"

          ip = IPAddr.new(candidate)
          ip.loopback? || ip.to_s == "0.0.0.0" || ip.to_s == "::1"
        rescue IPAddr::InvalidAddressError, SocketError
          false
        end

        def normalize_key(value)
          value.to_s.downcase.gsub(/[^a-z0-9]+/, "")
        end
    end
  end
end
