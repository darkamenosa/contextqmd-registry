# frozen_string_literal: true

require "test_helper"

class FetchRecipeTest < ActiveSupport::TestCase
  fixtures :accounts, :libraries, :versions, :fetch_recipes

  test "valid fetch recipe" do
    recipe = FetchRecipe.new(
      version: versions(:rails_stable),
      source_type: "git",
      url: "https://github.com/rails/rails.git"
    )
    assert recipe.valid?
  end

  test "requires source_type" do
    recipe = FetchRecipe.new(version: versions(:nextjs_stable), url: "https://example.com")
    assert_not recipe.valid?
    assert recipe.errors[:source_type].present?
  end

  test "requires url" do
    recipe = FetchRecipe.new(version: versions(:nextjs_stable), source_type: "http")
    assert_not recipe.valid?
    assert recipe.errors[:url].present?
  end

  test "belongs to version" do
    recipe = fetch_recipes(:nextjs_stable_recipe)
    assert_equal versions(:nextjs_stable), recipe.version
  end
end
