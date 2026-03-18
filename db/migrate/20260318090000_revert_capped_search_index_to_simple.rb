# frozen_string_literal: true

class RevertCappedSearchIndexToSimple < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # Drop any invalid index left by a failed concurrent create
    execute <<~SQL
      DROP INDEX CONCURRENTLY IF EXISTS index_pages_on_search_capped;
    SQL

    # Recreate the original simple expression index (no description cap)
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
    execute <<~SQL
      DROP INDEX CONCURRENTLY IF EXISTS index_pages_on_search;
    SQL

    execute <<~SQL
      CREATE INDEX CONCURRENTLY IF NOT EXISTS index_pages_on_search_capped
      ON pages
      USING gin (
        (
          setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
          setweight(to_tsvector('english', left(coalesce(description, ''), 400000)), 'B') ||
          setweight(to_tsvector('english', coalesce(path, '')), 'C')
        )
      );
    SQL
  end
end
