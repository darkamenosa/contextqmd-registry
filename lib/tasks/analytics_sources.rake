# frozen_string_literal: true

namespace :analytics do
  namespace :sources do
    desc "Backfill normalized source fields on ahoy visits"
    task backfill: :environment do
      batch_size = ENV.fetch("BATCH", 1000).to_i
      scope = Ahoy::Visit.order(:id)
      scope = scope.where(source_rule_version: [ nil, 0 ]) unless ENV["ALL"].present?

      total = scope.count
      processed = 0

      puts "Backfilling normalized source fields for #{total} visits in batches of #{batch_size}..."

      scope.find_in_batches(batch_size: batch_size) do |batch|
        batch.each do |visit|
          visit.refresh_source_dimensions!
          processed += 1
        end
        puts "Processed #{processed}/#{total}" if total.positive?
      end

      puts "Backfill complete."
    end

    desc "Report fallback-resolved sources so rules can be improved"
    task report_fallbacks: :environment do
      limit = ENV.fetch("LIMIT", 25).to_i

      rows = Ahoy::Visit
        .where("source_match_strategy LIKE ?", "fallback%")
        .group(:source_match_strategy, :source_label, :referring_domain, :utm_source)
        .order(Arel.sql("COUNT(*) DESC"))
        .limit(limit)
        .count

      if rows.empty?
        puts "No fallback-resolved sources found."
        next
      end

      puts "Top #{rows.size} fallback-resolved sources:"
      rows.each do |(strategy, label, domain, utm_source), count|
        puts [
          count.to_s.rjust(5),
          strategy.presence || "(none)",
          "label=#{label.presence || '(blank)'}",
          "domain=#{domain.presence || '(blank)'}",
          "utm_source=#{utm_source.presence || '(blank)'}"
        ].join("  ")
      end
    end
  end
end
