# frozen_string_literal: true

require "yaml"

Rails.application.config.x.analytics ||= OpenStruct.new

begin
  base_path  = Rails.root.join("config/analytics/custom_sources.yml")
  local_path = Rails.root.join("config/analytics/custom_sources.local.yml")
  base  = File.exist?(base_path)  ? YAML.safe_load(File.read(base_path))  : {}
  local = File.exist?(local_path) ? YAML.safe_load(File.read(local_path)) : {}
  base  = base.is_a?(Hash)  ? base  : {}
  local = local.is_a?(Hash) ? local : {}
  data = base.merge(local) { |_k, a, b| a.is_a?(Hash) && b.is_a?(Hash) ? a.merge(b) : b }

  sources = (data["sources"] || {}).each_with_object({}) do |(k, v), h|
    next if k.nil? || v.nil?
    h[k.to_s.downcase] = v.to_s
  end

  explicit_paid = Array(data["paid_aliases"]).map { |e| e.to_s.downcase }
  derived_paid = sources.keys.select { |k| k.end_with?("ad") || k.end_with?("ads") || k.include?("adwords") }
  paid = (explicit_paid + derived_paid).uniq

  Rails.application.config.x.analytics.alias_sources_map = sources.freeze
  Rails.application.config.x.analytics.paid_sources_set = paid.to_set.freeze
rescue => e
  Rails.logger.warn("[analytics_aliases] failed to load custom_sources.yml: #{e.class}: #{e.message}")
  Rails.application.config.x.analytics.alias_sources_map = {}.freeze
  Rails.application.config.x.analytics.paid_sources_set = Set.new.freeze
end
