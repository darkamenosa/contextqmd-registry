require "test_helper"

class CrawlRequestTest < ActiveSupport::TestCase
  setup do
    @identity, _account, _user = create_tenant
  end

  # --- Auto-detect source_type ---

  test "auto-detects git source_type from GitHub URL" do
    cr = CrawlRequest.new(url: "https://github.com/rails/rails", identity: @identity, status: "pending")
    cr.valid?
    assert_equal "git", cr.source_type
  end

  test "auto-detects git source_type from GitLab URL" do
    cr = CrawlRequest.new(url: "https://gitlab.com/group/project", identity: @identity, status: "pending")
    cr.valid?
    assert_equal "git", cr.source_type
  end

  test "auto-detects git source_type from Bitbucket URL" do
    cr = CrawlRequest.new(url: "https://bitbucket.org/owner/repo", identity: @identity, status: "pending")
    cr.valid?
    assert_equal "git", cr.source_type
  end

  test "auto-detects llms_txt source_type from URL" do
    cr = CrawlRequest.new(url: "https://react.dev/llms.txt", identity: @identity, status: "pending")
    cr.valid?
    assert_equal "llms_txt", cr.source_type
  end

  test "auto-detects website source_type for regular URLs" do
    cr = CrawlRequest.new(url: "https://docs.example.com/guide", identity: @identity, status: "pending")
    cr.valid?
    assert_equal "website", cr.source_type
  end

  test "auto-detect overrides explicit source_type from URL" do
    cr = CrawlRequest.new(url: "https://github.com/rails/rails", source_type: "website", identity: @identity, status: "pending")
    cr.valid?
    assert_equal "git", cr.source_type
  end

  test "auto-detects openapi source_type" do
    cr = CrawlRequest.new(url: "https://api.example.com/openapi.json", identity: @identity, status: "pending")
    cr.valid?
    assert_equal "openapi", cr.source_type
  end

  # --- Validations ---

  test "validates presence of url" do
    cr = CrawlRequest.new(source_type: "git", identity: @identity, status: "pending")
    assert_not cr.valid?
    assert_includes cr.errors[:url], "can't be blank"
  end

  test "auto-detect corrects invalid source_type from URL" do
    cr = CrawlRequest.new(url: "https://example.com", source_type: "invalid", identity: @identity, status: "pending")
    cr.valid?
    assert_equal "website", cr.source_type
  end

  # --- SSRF protection ---

  test "rejects localhost URLs" do
    cr = CrawlRequest.new(url: "http://localhost:3000/admin", identity: @identity, status: "pending")
    assert_not cr.valid?
    assert_includes cr.errors[:url], "must not point to a private address"
  end

  test "rejects 127.0.0.1 URLs" do
    cr = CrawlRequest.new(url: "http://127.0.0.1/secret", identity: @identity, status: "pending")
    assert_not cr.valid?
    assert_includes cr.errors[:url], "must not point to a private address"
  end

  test "rejects 0.0.0.0 URLs" do
    cr = CrawlRequest.new(url: "http://0.0.0.0:8080/api", identity: @identity, status: "pending")
    assert_not cr.valid?
    assert_includes cr.errors[:url], "must not point to a private address"
  end
end
