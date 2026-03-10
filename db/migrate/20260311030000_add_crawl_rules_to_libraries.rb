# frozen_string_literal: true

class AddCrawlRulesToLibraries < ActiveRecord::Migration[8.1]
  def change
    add_column :libraries, :crawl_rules, :jsonb, default: {}
  end
end
