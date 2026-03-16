# frozen_string_literal: true

class AddSearchTsvectorToPages < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :pages, :search_tsvector, :virtual,
      type: :tsvector,
      as: <<~SQL.squish,
        (
          setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
          setweight(to_tsvector('english', coalesce(description, '')), 'B') ||
          setweight(to_tsvector('english', coalesce(path, '')), 'C')
        )
      SQL
      stored: true

    add_index :pages, :search_tsvector,
      using: :gin,
      name: "index_pages_on_search_tsvector",
      algorithm: :concurrently
  end

  def down
    remove_index :pages, name: "index_pages_on_search_tsvector", algorithm: :concurrently
    remove_column :pages, :search_tsvector
  end
end
