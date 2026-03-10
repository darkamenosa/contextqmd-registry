# frozen_string_literal: true

class AddSearchIndexToPages < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # GIN index on tsvector for full-text search via pg_search
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

    # Unique index on page_uid scoped to version (ensure no dupes)
    add_index :pages, [ :version_id, :page_uid ], unique: true,
      name: "index_pages_on_version_id_and_page_uid",
      if_not_exists: true, algorithm: :concurrently
  end

  def down
    remove_index :pages, name: "index_pages_on_search", if_exists: true
    remove_index :pages, name: "index_pages_on_version_id_and_page_uid", if_exists: true
  end
end
