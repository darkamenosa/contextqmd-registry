# frozen_string_literal: true

require "test_helper"
require "rake"

Object.include Rake::DSL unless Object.included_modules.include?(Rake::DSL)
load Rails.root.join("lib/tasks/contextqmd_dev.rake") unless defined?(ContextqmdDevTasks)

class ContextqmdDevTasksTest < ActiveSupport::TestCase
  setup do
    @identity, = create_tenant
  end

  test "submit_catalog reads canonical metadata from catalog tsv" do
    path = Rails.root.join("tmp", "catalog-#{SecureRandom.hex(4)}.tsv")
    File.write(path, "act\tAct\thttps://github.com/nektos/act-docs\n")

    original_catalog_tsv = ENV["CATALOG_TSV"]
    original_submitter_email = ENV["SUBMITTER_EMAIL"]
    ENV["CATALOG_TSV"] = path.to_s
    ENV["SUBMITTER_EMAIL"] = @identity.email

    out = StringIO.new

    assert_difference -> { CrawlRequest.count }, 1 do
      ContextqmdDevTasks.submit_catalog!(out: out)
    end

    crawl_request = CrawlRequest.order(:id).last
    assert_equal "https://github.com/nektos/act-docs", crawl_request.url
    assert_equal "act", crawl_request.metadata["canonical_slug"]
    assert_equal "Act", crawl_request.metadata["canonical_display_name"]
  ensure
    ENV["CATALOG_TSV"] = original_catalog_tsv
    ENV["SUBMITTER_EMAIL"] = original_submitter_email
    FileUtils.rm_f(path) if path
  end
end
