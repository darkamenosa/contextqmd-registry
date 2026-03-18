# frozen_string_literal: true

class CapPageSearchTsvectorDescription < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INDEXED_DESCRIPTION_LIMIT = 400_000

  def up
    remove_index :pages, name: "index_pages_on_search", if_exists: true, algorithm: :concurrently

    if index_exists?(:pages, :search_tsvector, name: "index_pages_on_search_tsvector")
      remove_index :pages, name: "index_pages_on_search_tsvector", algorithm: :concurrently
    end

    remove_column :pages, :search_tsvector if column_exists?(:pages, :search_tsvector)

    add_column :pages, :search_tsvector, :virtual,
      type: :tsvector,
      as: capped_search_tsvector_expression,
      stored: true

    add_index :pages, :search_tsvector,
      using: :gin,
      name: "index_pages_on_search_tsvector",
      algorithm: :concurrently
  end

  def down
    if index_exists?(:pages, :search_tsvector, name: "index_pages_on_search_tsvector")
      remove_index :pages, name: "index_pages_on_search_tsvector", algorithm: :concurrently
    end

    remove_column :pages, :search_tsvector if column_exists?(:pages, :search_tsvector)

    add_column :pages, :search_tsvector, :virtual,
      type: :tsvector,
      as: uncapped_search_tsvector_expression,
      stored: true

    add_index :pages, :search_tsvector,
      using: :gin,
      name: "index_pages_on_search_tsvector",
      algorithm: :concurrently

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

  private

  def capped_search_tsvector_expression
    search_tsvector_expression("left(coalesce(description, ''), #{INDEXED_DESCRIPTION_LIMIT})")
  end

  def uncapped_search_tsvector_expression
    search_tsvector_expression("coalesce(description, '')")
  end

  def search_tsvector_expression(description_sql)
    <<~SQL.squish
      (
        setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
        setweight(to_tsvector('english', #{description_sql}), 'B') ||
        setweight(to_tsvector('english', coalesce(path, '')), 'C')
      )
    SQL
  end
end
