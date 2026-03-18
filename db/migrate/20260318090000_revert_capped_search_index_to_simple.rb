# frozen_string_literal: true

class RevertCappedSearchIndexToSimple < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # Drop invalid index left by failed concurrent create on production
    execute <<~SQL
      DROP INDEX CONCURRENTLY IF EXISTS index_pages_on_search_capped;
    SQL

    # Drop leftover indexes from previous migrations
    remove_index :pages, name: "index_pages_on_search_tsvector", if_exists: true, algorithm: :concurrently
    remove_index :pages, name: "index_pages_on_search", if_exists: true, algorithm: :concurrently

    # Drop stored generated column if it still exists (from 20260316094500)
    remove_column :pages, :search_tsvector if column_exists?(:pages, :search_tsvector)

    # Drop potentially invalid index left by interrupted concurrent create
    execute <<~SQL
      DROP INDEX CONCURRENTLY IF EXISTS index_pages_on_search;
    SQL

    # Recreate the simple expression index (no description cap)
    execute <<~SQL
      CREATE INDEX CONCURRENTLY IF NOT EXISTS index_pages_on_search
      ON pages
      USING gin (
        (
          setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
          setweight(to_tsvector('english', coalesce(description, '')), 'B') ||
          setweight(to_tsvector('english', coalesce(path, '')), 'C')
        )
      );
    SQL
  end

  def down
    remove_index :pages, name: "index_pages_on_search", if_exists: true, algorithm: :concurrently
  end
end
