class AddCachedStatsToLibraries < ActiveRecord::Migration[8.1]
  def change
    add_column :libraries, :versions_count, :integer, default: 0, null: false
    add_column :libraries, :total_pages_count, :integer, default: 0, null: false
    add_column :libraries, :latest_version_at, :datetime

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE libraries SET
            versions_count = (SELECT COUNT(*) FROM versions WHERE versions.library_id = libraries.id),
            total_pages_count = (SELECT COALESCE(SUM(versions.pages_count), 0) FROM versions WHERE versions.library_id = libraries.id),
            latest_version_at = (SELECT MAX(versions.created_at) FROM versions WHERE versions.library_id = libraries.id)
        SQL
      end
    end
  end
end
