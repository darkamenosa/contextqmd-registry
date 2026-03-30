# frozen_string_literal: true

class ScopeAnalyticsProfilesAndAllowedEventProperties < ActiveRecord::Migration[8.0]
  class MigrationAnalyticsProfile < ActiveRecord::Base
    self.table_name = "analytics_profiles"
  end

  class MigrationAnalyticsSetting < ActiveRecord::Base
    self.table_name = "analytics_settings"
  end

  class MigrationAllowedEventProperty < ActiveRecord::Base
    self.table_name = "analytics_allowed_event_properties"
  end

  def up
    create_table :analytics_allowed_event_properties do |t|
      t.references :analytics_site, null: false, foreign_key: true
      t.string :property_name, null: false
      t.timestamps
    end

    add_index :analytics_allowed_event_properties,
      [ :analytics_site_id, :property_name ],
      unique: true,
      name: "idx_analytics_allowed_event_properties_on_site_name"

    add_reference :analytics_profiles, :analytics_site, foreign_key: true
    add_reference :analytics_profile_keys, :analytics_site, foreign_key: true
    add_reference :analytics_profile_summaries, :analytics_site, foreign_key: true
    add_reference :analytics_profile_sessions, :analytics_site, foreign_key: true

    add_index :analytics_profiles, [ :analytics_site_id, :last_seen_at ], name: "index_analytics_profiles_on_site_id_and_last_seen_at"
    add_index :analytics_profile_summaries, [ :analytics_site_id, :last_seen_at ], name: "index_analytics_profile_summaries_on_site_id_and_last_seen_at"
    add_index :analytics_profile_sessions, [ :analytics_site_id, :started_at ], name: "index_analytics_profile_sessions_on_site_id_and_started_at"

    remove_index :analytics_profile_keys, [ :kind, :value ]
    add_index :analytics_profile_keys,
      "COALESCE(analytics_site_id, 0), kind, value",
      unique: true,
      name: "idx_analytics_profile_keys_on_site_scope_kind_value"

    backfill_profile_sites!
    backfill_projection_sites!
    backfill_allowed_event_properties!
  end

  def down
    remove_index :analytics_profile_keys, name: "idx_analytics_profile_keys_on_site_scope_kind_value"
    add_index :analytics_profile_keys, [ :kind, :value ], unique: true

    remove_index :analytics_profile_sessions, name: "index_analytics_profile_sessions_on_site_id_and_started_at"
    remove_index :analytics_profile_summaries, name: "index_analytics_profile_summaries_on_site_id_and_last_seen_at"
    remove_index :analytics_profiles, name: "index_analytics_profiles_on_site_id_and_last_seen_at"

    remove_reference :analytics_profile_sessions, :analytics_site, foreign_key: true
    remove_reference :analytics_profile_summaries, :analytics_site, foreign_key: true
    remove_reference :analytics_profile_keys, :analytics_site, foreign_key: true
    remove_reference :analytics_profiles, :analytics_site, foreign_key: true

    drop_table :analytics_allowed_event_properties
  end

  private
    def backfill_profile_sites!
      execute <<~SQL.squish
        UPDATE analytics_profiles
        SET analytics_site_id = resolved.analytics_site_id
        FROM (
          SELECT DISTINCT ON (analytics_profile_id)
            analytics_profile_id,
            analytics_site_id
          FROM ahoy_visits
          WHERE analytics_profile_id IS NOT NULL
            AND analytics_site_id IS NOT NULL
          ORDER BY analytics_profile_id, started_at DESC, id DESC
        ) resolved
        WHERE analytics_profiles.id = resolved.analytics_profile_id
          AND analytics_profiles.analytics_site_id IS NULL
      SQL
    end

    def backfill_projection_sites!
      execute <<~SQL.squish
        UPDATE analytics_profile_keys
        SET analytics_site_id = analytics_profiles.analytics_site_id
        FROM analytics_profiles
        WHERE analytics_profile_keys.analytics_profile_id = analytics_profiles.id
          AND analytics_profile_keys.analytics_site_id IS NULL
      SQL

      execute <<~SQL.squish
        UPDATE analytics_profile_summaries
        SET analytics_site_id = analytics_profiles.analytics_site_id
        FROM analytics_profiles
        WHERE analytics_profile_summaries.analytics_profile_id = analytics_profiles.id
          AND analytics_profile_summaries.analytics_site_id IS NULL
      SQL

      execute <<~SQL.squish
        UPDATE analytics_profile_sessions
        SET analytics_site_id = analytics_profiles.analytics_site_id
        FROM analytics_profiles
        WHERE analytics_profile_sessions.analytics_profile_id = analytics_profiles.id
          AND analytics_profile_sessions.analytics_site_id IS NULL
      SQL
    end

    def backfill_allowed_event_properties!
      MigrationAnalyticsSetting.where(key: "allowed_event_props").find_each do |setting|
        next if setting.analytics_site_id.blank?

        keys = JSON.parse(setting.value.to_s)
        Array(keys).map(&:to_s).map(&:strip).reject(&:blank?).uniq.each do |property_name|
          MigrationAllowedEventProperty.find_or_create_by!(
            analytics_site_id: setting.analytics_site_id,
            property_name: property_name
          )
        end
      rescue JSON::ParserError
        next
      end
    end
end
