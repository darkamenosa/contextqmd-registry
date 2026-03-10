# frozen_string_literal: true

class ConsolidateGitSourceTypes < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE crawl_requests SET source_type = 'git' WHERE source_type IN ('github', 'gitlab')
    SQL
    execute <<~SQL
      UPDATE fetch_recipes SET source_type = 'git' WHERE source_type IN ('github', 'gitlab', 'github_markdown')
    SQL
  end

  def down
    # Cannot reliably reverse — keep as "git"
  end
end
