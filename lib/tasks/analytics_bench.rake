# frozen_string_literal: true

namespace :analytics do
  desc "Run rollback-safe EXPLAIN ANALYZE benchmark queries against fake analytics load"
  task benchmark: :environment do
    conn = AnalyticsRecord.connection
    visits_count = ENV.fetch("BENCH_VISITS", "30000").to_i

    queries = {
      live_recent_visitors: <<~SQL,
        SELECT COUNT(DISTINCT ahoy_visits.visitor_token)
        FROM ahoy_visits
        WHERE ahoy_visits.id IN (
          SELECT DISTINCT ahoy_events.visit_id
          FROM ahoy_events
          WHERE time > NOW() - INTERVAL '5 minutes'
        )
      SQL
      pages_group_array_agg: <<~SQL,
        SELECT COALESCE(NULLIF(split_part(ahoy_events.properties->>'page', CHR(63), 1), ''), '(unknown)') AS page,
               ARRAY_AGG(DISTINCT ahoy_events.visit_id) AS visit_ids
        FROM ahoy_events
        INNER JOIN ahoy_visits ON ahoy_visits.id = ahoy_events.visit_id
        WHERE ahoy_events.name = 'pageview'
          AND ahoy_events.time BETWEEN date_trunc('day', NOW()) AND NOW()
          AND ahoy_visits.started_at BETWEEN date_trunc('day', NOW()) AND NOW()
        GROUP BY 1
      SQL
      sources_group_array_agg: <<~SQL
        SELECT COALESCE(referring_domain, 'Direct / None') AS source,
               ARRAY_AGG(ahoy_visits.id) AS visit_ids
        FROM ahoy_visits
        WHERE started_at BETWEEN date_trunc('day', NOW()) AND NOW()
        GROUP BY 1
      SQL
    }

    conn.transaction do
      conn.execute <<~SQL
        INSERT INTO ahoy_visits (
          visit_token, visitor_token, started_at, country, region, city,
          browser, os, screen_size, referring_domain, referrer,
          utm_source, utm_medium, hostname, latitude, longitude
        )
        SELECT
          'bench_visit_' || gs,
          'bench_visitor_' || (gs % GREATEST(#{visits_count / 3}, 1)),
          NOW() - ((gs % 86400) || ' seconds')::interval,
          (ARRAY['US','VN','DE','IN','GB'])[1 + (gs % 5)],
          (ARRAY['CA','HN','BE','KA','LN'])[1 + (gs % 5)],
          (ARRAY['San Francisco','Hanoi','Berlin','Bengaluru','London'])[1 + (gs % 5)],
          (ARRAY['Chrome','Safari','Firefox','Edge'])[1 + (gs % 4)],
          (ARRAY['Mac','Windows','Linux','iOS'])[1 + (gs % 4)],
          (ARRAY['Desktop','Laptop','Tablet','Mobile'])[1 + (gs % 4)],
          CASE WHEN gs % 6 = 0 THEN NULL ELSE (ARRAY['google.com','x.com','github.com','reddit.com','news.ycombinator.com'])[1 + (gs % 5)] END,
          CASE WHEN gs % 6 = 0 THEN NULL ELSE 'https://' || (ARRAY['google.com','x.com','github.com','reddit.com','news.ycombinator.com'])[1 + (gs % 5)] || '/ref/' || gs END,
          (ARRAY['google','twitter','github','reddit','newsletter'])[1 + (gs % 5)],
          (ARRAY['organic','social','referral','email'])[1 + (gs % 4)],
          'contextqmd.local',
          CASE WHEN gs % 3 = 0 THEN 37.77 ELSE 21.02 END,
          CASE WHEN gs % 3 = 0 THEN -122.42 ELSE 105.84 END
        FROM generate_series(1, #{visits_count}) AS gs
      SQL

      conn.execute <<~SQL
        INSERT INTO ahoy_events (visit_id, name, properties, time)
        SELECT
          v.id,
          'pageview',
          jsonb_build_object('page', (ARRAY['/','/docs','/pricing','/blog','/search','/guides','/api'])[1 + (s.n % 7)]),
          v.started_at + ((s.n * 15) || ' seconds')::interval
        FROM ahoy_visits v
        CROSS JOIN generate_series(1, 4) AS s(n)
        WHERE v.visit_token LIKE 'bench_visit_%'
      SQL

      conn.execute <<~SQL
        INSERT INTO ahoy_events (visit_id, name, properties, time)
        SELECT
          v.id,
          'engagement',
          jsonb_build_object('page', '/docs', 'engaged_ms', 20000, 'scroll_depth', 75),
          v.started_at + INTERVAL '90 seconds'
        FROM ahoy_visits v
        WHERE v.visit_token LIKE 'bench_visit_%'
          AND (v.id % 2) = 0
      SQL

      conn.execute("ANALYZE ahoy_visits")
      conn.execute("ANALYZE ahoy_events")

      puts({ bench_visits: visits_count }.to_json)

      queries.each do |name, sql|
        puts "\n=== #{name} ==="
        rows = conn.exec_query("EXPLAIN (ANALYZE, BUFFERS) #{sql}")
        puts rows.rows.flatten.join("\n")
      end

      raise ActiveRecord::Rollback
    end
  end
end
