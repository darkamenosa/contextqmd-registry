# frozen_string_literal: true

class CapPageSearchTsvectorDescription < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INDEXED_DESCRIPTION_LIMIT = 400_000
  LEGACY_SEARCH_INDEX_NAME = "index_pages_on_search"
  CAPPED_SEARCH_INDEX_NAME = "index_pages_on_search_capped"

  def up
    remove_index :pages, name: CAPPED_SEARCH_INDEX_NAME, if_exists: true, algorithm: :concurrently

    # Build the capped expression index first so the old app can keep searching
    # while the new index is created. Dropping/recreating the stored generated
    # column rewrites the whole table, so we remove that path entirely.
    execute <<~SQL
      CREATE INDEX CONCURRENTLY IF NOT EXISTS #{CAPPED_SEARCH_INDEX_NAME}
      ON pages
      USING gin (
        #{capped_search_tsvector_expression}
      );
    SQL

    if index_exists?(:pages, :search_tsvector, name: "index_pages_on_search_tsvector")
      remove_index :pages, name: "index_pages_on_search_tsvector", algorithm: :concurrently
    end

    remove_index :pages, name: LEGACY_SEARCH_INDEX_NAME, if_exists: true, algorithm: :concurrently

    remove_column :pages, :search_tsvector if column_exists?(:pages, :search_tsvector)
  end

  def down
    add_column :pages, :search_tsvector, :virtual,
      type: :tsvector,
      as: uncapped_search_tsvector_expression,
      stored: true unless column_exists?(:pages, :search_tsvector)

    unless index_exists?(:pages, :search_tsvector, name: "index_pages_on_search_tsvector")
      add_index :pages, :search_tsvector,
        using: :gin,
        name: "index_pages_on_search_tsvector",
        algorithm: :concurrently
    end

    execute <<~SQL
      CREATE INDEX CONCURRENTLY IF NOT EXISTS #{LEGACY_SEARCH_INDEX_NAME}
      ON pages
      USING gin (
        #{uncapped_search_tsvector_expression}
      );
    SQL

    remove_index :pages, name: CAPPED_SEARCH_INDEX_NAME, if_exists: true, algorithm: :concurrently
  end

  private

    def capped_search_tsvector_expression
      weighted_search_tsvector_expression("left(coalesce(description, ''), #{INDEXED_DESCRIPTION_LIMIT})")
    end

    def uncapped_search_tsvector_expression
      weighted_search_tsvector_expression("coalesce(description, '')")
    end

    def weighted_search_tsvector_expression(description_sql)
      <<~SQL.squish
        (
          setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
          setweight(to_tsvector('english', #{description_sql}), 'B') ||
          setweight(to_tsvector('english', coalesce(path, '')), 'C')
        )
      SQL
    end
end
