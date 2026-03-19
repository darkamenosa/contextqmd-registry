require "test_helper"

class CrawlRequestTest < ActiveSupport::TestCase
  setup do
    _identity, _account, @user = create_tenant
  end

  # --- Auto-detect source_type ---

  test "auto-detects github source_type from GitHub URL" do
    cr = CrawlRequest.new(url: "https://github.com/rails/rails", creator: @user, status: "pending")
    cr.valid?
    assert_equal "github", cr.source_type
  end

  test "auto-detects gitlab source_type from GitLab URL" do
    cr = CrawlRequest.new(url: "https://gitlab.com/group/project", creator: @user, status: "pending")
    cr.valid?
    assert_equal "gitlab", cr.source_type
  end

  test "auto-detects bitbucket source_type from Bitbucket URL" do
    cr = CrawlRequest.new(url: "https://bitbucket.org/owner/repo", creator: @user, status: "pending")
    cr.valid?
    assert_equal "bitbucket", cr.source_type
  end

  test "auto-detects llms_txt source_type from URL" do
    cr = CrawlRequest.new(url: "https://react.dev/llms.txt", creator: @user, status: "pending")
    cr.valid?
    assert_equal "llms_txt", cr.source_type
  end

  test "auto-detects website source_type for regular URLs" do
    cr = CrawlRequest.new(url: "https://docs.example.com/guide", creator: @user, status: "pending")
    cr.valid?
    assert_equal "website", cr.source_type
  end

  test "auto-detect overrides explicit source_type from URL" do
    cr = CrawlRequest.new(url: "https://github.com/rails/rails", source_type: "website", creator: @user, status: "pending")
    cr.valid?
    assert_equal "github", cr.source_type
  end

  test "auto-detects openapi source_type" do
    cr = CrawlRequest.new(url: "https://api.example.com/openapi.json", creator: @user, status: "pending")
    cr.valid?
    assert_equal "openapi", cr.source_type
  end

  # --- Validations ---

  test "validates presence of url" do
    cr = CrawlRequest.new(source_type: "git", creator: @user, status: "pending")
    assert_not cr.valid?
    assert_includes cr.errors[:url], "can't be blank"
  end

  test "auto-detect corrects invalid source_type from URL" do
    cr = CrawlRequest.new(url: "https://example.com", source_type: "invalid", creator: @user, status: "pending")
    cr.valid?
    assert_equal "website", cr.source_type
  end

  test "preserves library source source_type for scheduled generic git crawls" do
    _identity, account, _user = create_tenant(email: "scheduled-git-#{SecureRandom.hex(4)}@example.com")
    library = Library.create!(
      account: account,
      namespace: "scheduled-git",
      name: "repo",
      slug: "scheduled-git",
      display_name: "Scheduled Git"
    )
    source = library.library_sources.create!(
      url: "https://git.example.com/team/repo",
      source_type: "git",
      primary: true
    )

    cr = CrawlRequest.new(
      creator: @user,
      library: library,
      library_source: source,
      url: source.url,
      source_type: source.source_type,
      requested_bundle_visibility: "public",
      status: "pending"
    )

    cr.valid?
    assert_equal "git", cr.source_type
  end

  # --- SSRF protection ---

  test "rejects localhost URLs" do
    cr = CrawlRequest.new(url: "http://localhost:3000/admin", creator: @user, status: "pending")
    assert_not cr.valid?
    assert_includes cr.errors[:url], "must not point to a private address"
  end

  test "rejects 127.0.0.1 URLs" do
    cr = CrawlRequest.new(url: "http://127.0.0.1/secret", creator: @user, status: "pending")
    assert_not cr.valid?
    assert_includes cr.errors[:url], "must not point to a private address"
  end

  test "rejects 0.0.0.0 URLs" do
    cr = CrawlRequest.new(url: "http://0.0.0.0:8080/api", creator: @user, status: "pending")
    assert_not cr.valid?
    assert_includes cr.errors[:url], "must not point to a private address"
  end
end
