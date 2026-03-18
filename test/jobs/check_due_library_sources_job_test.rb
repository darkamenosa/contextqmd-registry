# frozen_string_literal: true

require "test_helper"

class CheckDueLibrarySourcesJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs

    _identity, account, _user = create_tenant(email: "check-due-#{SecureRandom.hex(4)}@example.com")
    @library = Library.create!(
      account: account,
      namespace: "check-due",
      name: "docs",
      slug: "check-due-docs",
      display_name: "Check Due Docs"
    )
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    ActiveJob::Base.queue_adapter = @original_queue_adapter
  end

  test "enqueues only due primary version-checkable sources and claims them" do
    due = @library.library_sources.create!(
      url: "https://github.com/example/docs",
      source_type: "github",
      primary: true,
      next_version_check_at: 1.hour.ago
    )
    @library.library_sources.create!(
      url: "https://github.com/example/docs-mirror",
      source_type: "github",
      primary: false,
      next_version_check_at: 1.hour.ago
    )
    other_library = Library.create!(
      account: @library.account,
      namespace: "check-due-website",
      name: "docs",
      slug: "check-due-website",
      display_name: "Check Due Website"
    )
    website_source = other_library.library_sources.create!(
      url: "https://docs.example.com",
      source_type: "website",
      primary: true,
      next_version_check_at: 1.hour.ago
    )

    assert_enqueued_jobs 2, only: CheckLibrarySourceJob do
      CheckDueLibrarySourcesJob.perform_now
    end

    due.reload
    website_source.reload
    assert due.version_check_claimed_at.present?
    assert website_source.version_check_claimed_at.present?
  end

  test "does not enqueue a due source twice while it is still claimed" do
    @library.library_sources.create!(
      url: "https://github.com/example/docs",
      source_type: "github",
      primary: true,
      next_version_check_at: 1.hour.ago
    )

    CheckDueLibrarySourcesJob.perform_now
    assert_enqueued_jobs 1, only: CheckLibrarySourceJob

    assert_no_enqueued_jobs only: CheckLibrarySourceJob do
      CheckDueLibrarySourcesJob.perform_now
    end
  end
end
