# frozen_string_literal: true

class AddSearchTsvectorToPages < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    unless column_exists?(:pages, :search_tsvector)
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
    end

    unless index_exists?(:pages, :search_tsvector, name: "index_pages_on_search_tsvector")
      add_index :pages, :search_tsvector,
        using: :gin,
        name: "index_pages_on_search_tsvector",
        algorithm: :concurrently
    end
  end

  def down
    if index_exists?(:pages, :search_tsvector, name: "index_pages_on_search_tsvector")
      remove_index :pages, name: "index_pages_on_search_tsvector", algorithm: :concurrently
    end

    remove_column :pages, :search_tsvector if column_exists?(:pages, :search_tsvector)
  end
end
