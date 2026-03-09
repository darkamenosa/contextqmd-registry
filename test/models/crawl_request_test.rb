require "test_helper"

class CrawlRequestTest < ActiveSupport::TestCase
  setup do
    @identity, _account, _user = create_tenant
  end

  # --- Auto-detect source_type ---

  test "auto-detects github source_type from URL" do
    cr = CrawlRequest.new(url: "https://github.com/rails/rails", identity: @identity, status: "pending")
    cr.valid?
    assert_equal "github", cr.source_type
  end

  test "auto-detects gitlab source_type from URL" do
    cr = CrawlRequest.new(url: "https://gitlab.com/group/project", identity: @identity, status: "pending")
    cr.valid?
    assert_equal "gitlab", cr.source_type
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

  test "auto-detect overrides source_type based on URL" do
    cr = CrawlRequest.new(url: "https://github.com/rails/rails", source_type: "website", identity: @identity, status: "pending")
    cr.valid?
    assert_equal "github", cr.source_type
  end

  test "auto-detects openapi source_type" do
    cr = CrawlRequest.new(url: "https://api.example.com/openapi.json", identity: @identity, status: "pending")
    cr.valid?
    assert_equal "openapi", cr.source_type
  end

  # --- Validations ---

  test "validates presence of url" do
    cr = CrawlRequest.new(source_type: "github", identity: @identity, status: "pending")
    assert_not cr.valid?
    assert_includes cr.errors[:url], "can't be blank"
  end

  test "auto-detect always runs so invalid source_type gets corrected" do
    cr = CrawlRequest.new(url: "https://example.com", source_type: "invalid", identity: @identity, status: "pending")
    cr.valid?
    # Auto-detect corrects the invalid source_type based on URL
    assert_equal "website", cr.source_type
  end
end
