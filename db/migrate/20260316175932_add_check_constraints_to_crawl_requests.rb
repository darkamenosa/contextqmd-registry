class AddCheckConstraintsToCrawlRequests < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :crawl_requests,
      "status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')",
      name: "crawl_requests_status_check"

    add_check_constraint :crawl_requests,
      "source_type IN ('github', 'gitlab', 'bitbucket', 'git', 'website', 'openapi', 'llms_txt')",
      name: "crawl_requests_source_type_check"

    add_check_constraint :crawl_requests,
      "requested_bundle_visibility IN ('public', 'private')",
      name: "crawl_requests_bundle_visibility_check"
  end
end
