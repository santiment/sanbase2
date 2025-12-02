defmodule Sanbase.Insight.CategorizerTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import Mox

  alias Sanbase.Insight.{Category, PostCategory, Categorizer}
  alias Sanbase.Repo

  setup :verify_on_exit!

  setup do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    categories = [
      %{
        name: "On-chain market analysis",
        description: "On-chain analysis",
        inserted_at: now,
        updated_at: now
      },
      %{
        name: "Social Trends market analysis",
        description: "Social trends",
        inserted_at: now,
        updated_at: now
      },
      %{
        name: "Education on using Santiment",
        description: "Education",
        inserted_at: now,
        updated_at: now
      },
      %{
        name: "Product launch/update",
        description: "Product",
        inserted_at: now,
        updated_at: now
      },
      %{
        name: "Promotional discount/sale",
        description: "Promotional",
        inserted_at: now,
        updated_at: now
      }
    ]

    Enum.each(categories, fn cat ->
      Repo.insert_all(Category, [cat], on_conflict: :nothing, conflict_target: [:name])
    end)

    :ok
  end

  describe "categorize_insight/2" do
    test "does not override human categories when force: false" do
      user = insert(:user)
      post = insert(:post, user: user)

      # Create human-sourced category
      category = Repo.get_by(Category, name: "On-chain market analysis")
      PostCategory.override_with_human_categories(post.id, [category.id])

      result = Categorizer.categorize_insight(post.id, save: true, force: false)

      assert {:error, "Cannot override human-sourced categories. Use force: true to override."} =
               result

      # Verify human category still exists
      categories = PostCategory.get_post_categories(post.id)
      assert length(categories) == 1
      assert Enum.at(categories, 0).source == "human"
    end

    test "validates category names exist in database" do
      user = insert(:user)
      _post = insert(:post, user: user, title: "Test", text: "Test content")

      # Test that invalid categories are rejected
      invalid_category_names = ["Invalid Category Name"]
      categories = Category.by_names(invalid_category_names)
      assert length(categories) == 0
    end
  end
end
