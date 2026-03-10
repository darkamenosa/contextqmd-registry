class AddSourceTypeToLibraries < ActiveRecord::Migration[8.1]
  def change
    add_column :libraries, :source_type, :string

    # Backfill from each library's most recent fetch_recipe
    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE libraries SET source_type = subq.source_type
          FROM (
            SELECT DISTINCT ON (v.library_id)
              v.library_id, fr.source_type
            FROM versions v
            JOIN fetch_recipes fr ON fr.version_id = v.id
            ORDER BY v.library_id, v.generated_at DESC NULLS LAST
          ) subq
          WHERE libraries.id = subq.library_id
        SQL
      end
    end
  end
end
