class AddEngagedMsTotalToAnalyticsProfileSessions < ActiveRecord::Migration[8.0]
  def up
    add_column :analytics_profile_sessions, :engaged_ms_total, :integer, null: false, default: 0

    execute <<~SQL
      UPDATE analytics_profile_sessions
      SET engaged_ms_total = COALESCE(event_totals.engaged_ms_total, 0)
      FROM (
        SELECT
          visit_id,
          SUM(
            CASE
              WHEN name = 'engagement'
                AND properties IS NOT NULL
                AND NULLIF(properties->>'engaged_ms', '') IS NOT NULL
              THEN GREATEST((properties->>'engaged_ms')::integer, 0)
              ELSE 0
            END
          ) AS engaged_ms_total
        FROM ahoy_events
        GROUP BY visit_id
      ) AS event_totals
      WHERE analytics_profile_sessions.visit_id = event_totals.visit_id
    SQL
  end

  def down
    remove_column :analytics_profile_sessions, :engaged_ms_total
  end
end
