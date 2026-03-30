class CreateAnalyticsSiteTrackingRules < ActiveRecord::Migration[8.1]
  class MigrationSetting < ActiveRecord::Base
    self.table_name = "analytics_settings"
  end

  def up
    create_table :analytics_site_tracking_rules do |t|
      t.references :analytics_site, null: false, foreign_key: true, index: { unique: true }
      t.jsonb :include_paths, null: false, default: []
      t.jsonb :exclude_paths, null: false, default: []

      t.timestamps
    end

    say_with_time "Migrating analytics_settings tracking_rules into analytics_site_tracking_rules" do
      MigrationSetting.where(key: "tracking_rules").find_each do |setting|
        payload = JSON.parse(setting.value.presence || "{}") rescue {}
        next if setting.analytics_site_id.blank?

        execute <<~SQL.squish
          INSERT INTO analytics_site_tracking_rules (
            analytics_site_id,
            include_paths,
            exclude_paths,
            created_at,
            updated_at
          )
          VALUES (
            #{Integer(setting.analytics_site_id)},
            #{connection.quote((payload["include_paths"] || []).to_json)}::jsonb,
            #{connection.quote((payload["exclude_paths"] || []).to_json)}::jsonb,
            CURRENT_TIMESTAMP,
            CURRENT_TIMESTAMP
          )
          ON CONFLICT (analytics_site_id)
          DO UPDATE SET
            include_paths = EXCLUDED.include_paths,
            exclude_paths = EXCLUDED.exclude_paths,
            updated_at = CURRENT_TIMESTAMP
        SQL
      end

      MigrationSetting.where(key: "tracking_rules").delete_all
    end
  end

  def down
    drop_table :analytics_site_tracking_rules
  end
end
