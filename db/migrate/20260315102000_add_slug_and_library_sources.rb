# frozen_string_literal: true

require "set"

class AddSlugAndLibrarySources < ActiveRecord::Migration[8.0]
  GENERIC_SOURCE_NAMES = %w[
    api book doc docs documentation guide guides handbook manual manuals
    reference references site website wiki
  ].freeze

  class MigrationLibrary < ApplicationRecord
    self.table_name = "libraries"
  end

  def up
    add_column :libraries, :slug, :string

    MigrationLibrary.reset_column_information
    taken_slugs = Set.new
    MigrationLibrary.find_each do |library|
      library.update_columns(slug: backfill_slug(library, taken_slugs))
    end

    change_column_null :libraries, :slug, false
    add_index :libraries, :slug, unique: true

    create_table :library_sources do |t|
      t.references :library, null: false, foreign_key: true
      t.string :url, null: false
      t.string :source_type, null: false
      t.boolean :active, null: false, default: true
      t.boolean :primary, null: false, default: false
      t.jsonb :crawl_rules, null: false, default: {}
      t.datetime :last_crawled_at
      t.timestamps
    end

    add_index :library_sources, :url, unique: true
    add_index :library_sources, [ :library_id, :primary ], unique: true, where: "\"primary\" = TRUE"

    add_reference :crawl_requests, :library_source, foreign_key: true
    add_reference :fetch_recipes, :library_source, foreign_key: true

    backfill_primary_sources
  end

  def down
    remove_reference :fetch_recipes, :library_source, foreign_key: true
    remove_reference :crawl_requests, :library_source, foreign_key: true
    drop_table :library_sources
    remove_index :libraries, :slug
    remove_column :libraries, :slug
  end

  private

    def backfill_primary_sources
      say_with_time "Backfilling library sources" do
        MigrationLibrary.find_each do |library|
          source_url = ActiveRecord::Base.connection.select_value(<<~SQL.squish)
            SELECT fetch_recipes.url
            FROM versions
            INNER JOIN fetch_recipes ON fetch_recipes.version_id = versions.id
            WHERE versions.library_id = #{library.id}
            ORDER BY versions.created_at DESC
            LIMIT 1
          SQL

          source_type = library.source_type.presence || "website"
          next if source_url.blank?

          execute <<~SQL.squish
            INSERT INTO library_sources (library_id, url, source_type, active, "primary", crawl_rules, created_at, updated_at)
            VALUES (
              #{library.id},
              #{quote(source_url)},
              #{quote(source_type)},
              TRUE,
              TRUE,
              '{}'::jsonb,
              NOW(),
              NOW()
            )
            ON CONFLICT (url) DO NOTHING
          SQL

          source_id = ActiveRecord::Base.connection.select_value(
            "SELECT id FROM library_sources WHERE url = #{quote(source_url)} LIMIT 1"
          )
          next unless source_id

          execute <<~SQL.squish
            UPDATE fetch_recipes
            SET library_source_id = #{source_id}
            FROM versions
            WHERE fetch_recipes.version_id = versions.id
              AND versions.library_id = #{library.id}
              AND fetch_recipes.library_source_id IS NULL
          SQL
        end
      end
    end

    def slugify(value, fallback:)
      slug = value.to_s.tr("_", "-").parameterize(separator: "-")
      slug.presence || fallback
    end

    def backfill_slug(library, taken_slugs)
      base_slug = slugify(preferred_slug_source(library), fallback: "library-#{library.id}")
      slug = unique_slug(base_slug, library, taken_slugs)
      taken_slugs << slug
      slug
    end

    def preferred_slug_source(library)
      name = library.name.to_s
      namespace = library.namespace.to_s

      return namespace if GENERIC_SOURCE_NAMES.include?(name.downcase)

      name.presence || namespace.presence
    end

    def unique_slug(base_slug, library, taken_slugs)
      return base_slug unless taken_slugs.include?(base_slug)

      namespace_slug = slugify(library.namespace, fallback: "library-#{library.id}")
      name_slug = slugify(library.name, fallback: "library-#{library.id}")
      candidates = []
      namespace_name_slug = [ namespace_slug, name_slug ].uniq.join("-")
      candidates << namespace_name_slug unless namespace_name_slug == base_slug
      candidates << "#{namespace_slug}-#{base_slug}" unless namespace_slug == base_slug
      candidates << "#{base_slug}-#{library.id}"

      candidates.each do |candidate|
        return candidate unless taken_slugs.include?(candidate)
      end

      suffix = 2
      loop do
        candidate = "#{base_slug}-#{library.id}-#{suffix}"
        return candidate unless taken_slugs.include?(candidate)

        suffix += 1
      end
    end
end
