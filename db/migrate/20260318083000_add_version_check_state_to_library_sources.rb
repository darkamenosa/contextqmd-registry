# frozen_string_literal: true

class AddVersionCheckStateToLibrarySources < ActiveRecord::Migration[8.1]
  VERSION_CHECKABLE_SOURCE_TYPES = %w[github gitlab bitbucket git llms_txt openapi].freeze

  def up
    add_column :library_sources, :last_version_check_at, :datetime
    add_column :library_sources, :next_version_check_at, :datetime
    add_column :library_sources, :last_version_change_at, :datetime
    add_column :library_sources, :version_check_claimed_at, :datetime
    add_column :library_sources, :consecutive_no_change_checks, :integer, default: 0, null: false

    add_index :library_sources, :next_version_check_at

    quoted_types = VERSION_CHECKABLE_SOURCE_TYPES.map { |type| connection.quote(type) }.join(", ")

    execute <<~SQL.squish
      UPDATE library_sources
      SET next_version_check_at = NOW() + ((random() * 7 * 24 * 60 * 60)::int * INTERVAL '1 second')
      WHERE "primary" = TRUE
        AND active = TRUE
        AND source_type IN (#{quoted_types})
        AND next_version_check_at IS NULL
    SQL
  end

  def down
    remove_index :library_sources, :next_version_check_at

    remove_column :library_sources, :consecutive_no_change_checks
    remove_column :library_sources, :version_check_claimed_at
    remove_column :library_sources, :last_version_change_at
    remove_column :library_sources, :next_version_check_at
    remove_column :library_sources, :last_version_check_at
  end
end
