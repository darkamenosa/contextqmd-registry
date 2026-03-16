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
end
