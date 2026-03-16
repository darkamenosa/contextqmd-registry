# frozen_string_literal: true

require "test_helper"

class DocsFetcher::LibraryIdentityTest < ActiveSupport::TestCase
  test "git generic docs repos resolve to the owner slug" do
    identity = DocsFetcher::LibraryIdentity.from_git(
      owner: "laravel",
      repo_name: "docs",
      source_url: "https://github.com/laravel/docs"
    )

    assert_equal "laravel", identity[:slug]
    assert_equal "laravel", identity[:namespace]
    assert_equal "docs", identity[:name]
    assert_equal "Laravel", identity[:display_name]
    assert_includes identity[:aliases], "laravel/docs"
    refute_includes identity[:aliases], "github.com"
  end

  test "git identities do not include owner-only aliases for non-generic repos" do
    identity = DocsFetcher::LibraryIdentity.from_git(
      owner: "rust-lang",
      repo_name: "cargo",
      source_url: "https://github.com/rust-lang/cargo"
    )

    assert_equal "cargo", identity[:slug]
    assert_includes identity[:aliases], "cargo"
    assert_includes identity[:aliases], "rust-lang/cargo"
    refute_includes identity[:aliases], "rust-lang"
  end

  test "llms identities use host-derived product slug and clean display title" do
    identity = DocsFetcher::LibraryIdentity.from_llms(
      uri: URI.parse("https://react.dev/llms-full.txt"),
      title: "React Documentation"
    )

    assert_equal "react", identity[:slug]
    assert_equal "react", identity[:namespace]
    assert_equal "react", identity[:name]
    assert_equal "React", identity[:display_name]
  end

  test "website identities stay conservative about page titles" do
    identity = DocsFetcher::LibraryIdentity.from_website(
      uri: URI.parse("https://laravel.com/docs"),
      title: "Laravel AI SDK"
    )

    assert_equal "laravel", identity[:slug]
    assert_equal "Laravel", identity[:display_name]
  end

  test "openapi identities use the spec title as the canonical product" do
    identity = DocsFetcher::LibraryIdentity.from_openapi(
      uri: URI.parse("https://api.example.com/openapi.json"),
      title: "Pet Store API"
    )

    assert_equal "pet-store", identity[:slug]
    assert_equal "pet-store", identity[:namespace]
    assert_equal "pet-store", identity[:name]
    assert_equal "Pet Store", identity[:display_name]
    assert_includes identity[:aliases], "apiexamplecom"
  end

  test "openapi identities fall back to the host slug for generic titles" do
    identity = DocsFetcher::LibraryIdentity.from_openapi(
      uri: URI.parse("https://payments.example.com/openapi.json"),
      title: "API Reference"
    )

    assert_equal "payments", identity[:slug]
    assert_equal "payments", identity[:namespace]
    assert_equal "payments", identity[:name]
    assert_equal "Payments", identity[:display_name]
  end

  test "generic two-label docs hosts fall back to the first meaningful path segment" do
    identity = DocsFetcher::LibraryIdentity.from_llms(
      uri: URI.parse("https://docs.rs/serde/llms.txt"),
      title: "Serde Documentation"
    )

    assert_equal "serde", identity[:slug]
    assert_equal "Serde", identity[:display_name]
  end

  # --- Generic repo name detection ---

  test "git generic repo names (core, cli, server) resolve to owner slug" do
    { "core" => "adonisjs", "cli" => "netlify", "server" => "triton-inference-server",
      "sdk" => "stripe", "framework" => "laravel", "app" => "heroku" }.each do |repo, owner|
      identity = DocsFetcher::LibraryIdentity.from_git(
        owner: owner, repo_name: repo, source_url: "https://github.com/#{owner}/#{repo}"
      )
      assert_equal owner, identity[:slug], "#{owner}/#{repo} should use owner slug"
    end
  end

  # --- Docs website repo detection ---

  test "git docs.nestjs.com resolves to nestjs" do
    identity = DocsFetcher::LibraryIdentity.from_git(
      owner: "nestjs", repo_name: "docs.nestjs.com",
      source_url: "https://github.com/nestjs/docs.nestjs.com"
    )
    assert_equal "nestjs", identity[:slug]
  end

  test "git tailwindcss.com resolves to tailwindcss" do
    identity = DocsFetcher::LibraryIdentity.from_git(
      owner: "tailwindlabs", repo_name: "tailwindcss.com",
      source_url: "https://github.com/tailwindlabs/tailwindcss.com"
    )
    assert_equal "tailwindcss", identity[:slug]
  end

  test "git react.dev resolves to react" do
    identity = DocsFetcher::LibraryIdentity.from_git(
      owner: "reactjs", repo_name: "react.dev",
      source_url: "https://github.com/reactjs/react.dev"
    )
    assert_equal "react", identity[:slug]
  end

  test "git expressjs.com resolves to expressjs" do
    identity = DocsFetcher::LibraryIdentity.from_git(
      owner: "expressjs", repo_name: "expressjs.com",
      source_url: "https://github.com/expressjs/expressjs.com"
    )
    assert_equal "expressjs", identity[:slug]
  end

  test "git kamal-site resolves to kamal" do
    identity = DocsFetcher::LibraryIdentity.from_git(
      owner: "basecamp", repo_name: "kamal-site",
      source_url: "https://github.com/basecamp/kamal-site"
    )
    assert_equal "kamal", identity[:slug]
  end

  # --- Docs repo suffix detection ---

  test "git drizzle-orm-docs resolves to drizzle-orm" do
    identity = DocsFetcher::LibraryIdentity.from_git(
      owner: "drizzle-team", repo_name: "drizzle-orm-docs",
      source_url: "https://github.com/drizzle-team/drizzle-orm-docs"
    )
    assert_equal "drizzle-orm", identity[:slug]
  end

  test "git ansible-documentation resolves to ansible" do
    identity = DocsFetcher::LibraryIdentity.from_git(
      owner: "ansible", repo_name: "ansible-documentation",
      source_url: "https://github.com/ansible/ansible-documentation"
    )

    assert_equal "ansible", identity[:slug]
    assert_equal "Ansible", identity[:display_name]
  end

  # --- Generic language names ---

  test "git generic language repo names resolve to owner slug" do
    identity = DocsFetcher::LibraryIdentity.from_git(
      owner: "clerk", repo_name: "javascript",
      source_url: "https://github.com/clerk/javascript"
    )
    assert_equal "clerk", identity[:slug]
  end

  test "git language repos keep their own slug when owner IS the language project" do
    # rust-lang/rust → rust (not rust-lang)
    identity = DocsFetcher::LibraryIdentity.from_git(
      owner: "rust-lang", repo_name: "rust",
      source_url: "https://github.com/rust-lang/rust"
    )
    assert_equal "rust", identity[:slug]

    # golang/go → go (not golang)
    identity = DocsFetcher::LibraryIdentity.from_git(
      owner: "golang", repo_name: "go",
      source_url: "https://github.com/golang/go"
    )
    assert_equal "go", identity[:slug]

    # swiftlang/swift → swift (not swiftlang)
    identity = DocsFetcher::LibraryIdentity.from_git(
      owner: "swiftlang", repo_name: "swift",
      source_url: "https://github.com/swiftlang/swift"
    )
    assert_equal "swift", identity[:slug]
  end

  # --- Docs suffix safety ---

  test "git docs suffix not stripped when owner equals repo" do
    # terraform-docs/terraform-docs → terraform-docs (not terraform)
    identity = DocsFetcher::LibraryIdentity.from_git(
      owner: "terraform-docs", repo_name: "terraform-docs",
      source_url: "https://github.com/terraform-docs/terraform-docs"
    )
    assert_equal "terraform-docs", identity[:slug]
  end

  # --- Normal repos should not be affected ---

  test "git normal repo names are not changed" do
    %w[react next.js fastapi django flask express].each do |repo|
      identity = DocsFetcher::LibraryIdentity.from_git(
        owner: "some-org", repo_name: repo,
        source_url: "https://github.com/some-org/#{repo}"
      )
      expected = repo.tr("_.", "-").parameterize(separator: "-")
      assert_equal expected, identity[:slug], "#{repo} should keep its own slug"
    end
  end
end
