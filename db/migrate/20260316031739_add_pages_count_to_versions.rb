class AddPagesCountToVersions < ActiveRecord::Migration[8.1]
  def up
    add_column :versions, :pages_count, :integer, default: 0, null: false

    # Backfill from actual counts
    execute <<~SQL.squish
      UPDATE versions
      SET pages_count = (SELECT COUNT(*) FROM pages WHERE pages.version_id = versions.id)
    SQL
  end

  def down
    remove_column :versions, :pages_count
  end
end
