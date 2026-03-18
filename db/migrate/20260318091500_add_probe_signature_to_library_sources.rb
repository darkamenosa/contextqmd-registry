# frozen_string_literal: true

class AddProbeSignatureToLibrarySources < ActiveRecord::Migration[8.1]
  def up
    add_column :library_sources, :last_probe_signature, :string

    execute <<~SQL.squish
      UPDATE library_sources
      SET next_version_check_at = NOW() + ((random() * 30 * 24 * 60 * 60)::int * INTERVAL '1 second')
      WHERE "primary" = TRUE
        AND active = TRUE
        AND source_type = 'website'
        AND next_version_check_at IS NULL
    SQL
  end

  def down
    remove_column :library_sources, :last_probe_signature
  end
end
