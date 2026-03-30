# frozen_string_literal: true

class CreateAnalyticsSitesAndBoundaries < ActiveRecord::Migration[8.0]
  class MigrationSite < ActiveRecord::Base
    self.table_name = "analytics_sites"
  end

  class MigrationSiteBoundary < ActiveRecord::Base
    self.table_name = "analytics_site_boundaries"
  end

  class MigrationVisit < ActiveRecord::Base
    self.table_name = "ahoy_visits"
  end

  def up
    create_table :analytics_sites do |t|
      t.string :public_id, null: false
      t.string :owner_type
      t.string :owner_key
      t.string :name, null: false
      t.string :canonical_hostname
      t.string :time_zone
      t.string :status, null: false, default: "active"
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :analytics_sites, :public_id, unique: true
    add_index :analytics_sites, [ :owner_type, :owner_key ]
    add_index :analytics_sites, :canonical_hostname

    create_table :analytics_site_boundaries do |t|
      t.references :analytics_site, null: false, foreign_key: true
      t.string :host, null: false
      t.string :path_prefix, null: false, default: "/"
      t.integer :priority, null: false, default: 0
      t.boolean :primary, null: false, default: false
      t.timestamps
    end

    add_index :analytics_site_boundaries, [ :host, :path_prefix ], unique: true
    add_index :analytics_site_boundaries, :host
    add_index :analytics_site_boundaries, [ :analytics_site_id, :primary ], unique: true, where: "\"primary\" = TRUE", name: "index_analytics_site_boundaries_on_site_primary"

    add_reference :ahoy_visits, :analytics_site, foreign_key: true
    add_reference :ahoy_visits, :analytics_site_boundary, foreign_key: true
    add_reference :ahoy_events, :analytics_site, foreign_key: true
    add_reference :ahoy_events, :analytics_site_boundary, foreign_key: true

    add_index :ahoy_visits, [ :analytics_site_id, :started_at ], name: "index_ahoy_visits_on_site_id_and_started_at"
    add_index :ahoy_events, [ :analytics_site_id, :time ], name: "index_ahoy_events_on_site_id_and_time"

    backfill_sites_from_visit_hostnames!
    backfill_event_site_scope!
  end

  def down
    remove_index :ahoy_events, name: "index_ahoy_events_on_site_id_and_time"
    remove_index :ahoy_visits, name: "index_ahoy_visits_on_site_id_and_started_at"

    remove_reference :ahoy_events, :analytics_site_boundary, foreign_key: true
    remove_reference :ahoy_events, :analytics_site, foreign_key: true
    remove_reference :ahoy_visits, :analytics_site_boundary, foreign_key: true
    remove_reference :ahoy_visits, :analytics_site, foreign_key: true

    drop_table :analytics_site_boundaries
    drop_table :analytics_sites
  end

  private
    def backfill_sites_from_visit_hostnames!
      say_with_time "Backfilling analytics sites from visit hostnames" do
        normalized_hosts = MigrationVisit.distinct.pluck(:hostname).filter_map do |hostname|
          normalize_host(hostname)
        end.uniq

        normalized_hosts.each do |host|
          site = MigrationSite.create!(
            public_id: SecureRandom.uuid,
            name: host,
            canonical_hostname: host,
            status: "active",
            metadata: {}
          )

          boundary = MigrationSiteBoundary.create!(
            analytics_site_id: site.id,
            host: host,
            path_prefix: "/",
            priority: 0,
            primary: true
          )

          MigrationVisit.where("LOWER(hostname) = ?", host).update_all(
            analytics_site_id: site.id,
            analytics_site_boundary_id: boundary.id
          )
        end
      end
    end

    def backfill_event_site_scope!
      say_with_time "Backfilling analytics event site scope from visits" do
        execute <<~SQL.squish
          UPDATE ahoy_events
             SET analytics_site_id = ahoy_visits.analytics_site_id,
                 analytics_site_boundary_id = ahoy_visits.analytics_site_boundary_id
            FROM ahoy_visits
           WHERE ahoy_events.visit_id = ahoy_visits.id
        SQL
      end
    end

    def normalize_host(host)
      value = host.to_s.strip.downcase
      value = value.sub(/:\d+\z/, "")
      value.presence
    end
end
