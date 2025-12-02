defmodule Sanbase.Insight.PostCategoryTest do
  use Sanbase.DataCase, async: true

  import Sanbase.Factory

  alias Sanbase.Insight.{Category, PostCategory}
  alias Sanbase.Repo

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
      }
    ]

    Enum.each(categories, fn cat ->
      Repo.insert_all(Category, [cat], on_conflict: :nothing, conflict_target: [:name])
    end)

    :ok
  end

  describe "assign_categories/3" do
    test "assigns AI-sourced categories to a post" do
      user = insert(:user)
      post = insert(:post, user: user)

      category1 = Repo.get_by(Category, name: "On-chain market analysis")
      category2 = Repo.get_by(Category, name: "Social Trends market analysis")

      {:ok, _} = PostCategory.assign_categories(post.id, [category1.id, category2.id], "ai")

      categories = PostCategory.get_post_categories(post.id)
      assert length(categories) == 2

      category_names = Enum.map(categories, & &1.category_name)
      assert "On-chain market analysis" in category_names
      assert "Social Trends market analysis" in category_names

      assert Enum.all?(categories, &(&1.source == "ai"))
    end

    test "replaces existing categories with same source" do
      user = insert(:user)
      post = insert(:post, user: user)

      category1 = Repo.get_by(Category, name: "On-chain market analysis")
      category2 = Repo.get_by(Category, name: "Social Trends market analysis")
      category3 = Repo.get_by(Category, name: "Education on using Santiment")

      # Assign initial categories
      {:ok, _} = PostCategory.assign_categories(post.id, [category1.id], "ai")

      # Replace with new categories
      {:ok, _} = PostCategory.assign_categories(post.id, [category2.id, category3.id], "ai")

      categories = PostCategory.get_post_categories(post.id)
      assert length(categories) == 2

      category_names = Enum.map(categories, & &1.category_name)
      assert "Social Trends market analysis" in category_names
      assert "Education on using Santiment" in category_names
      refute "On-chain market analysis" in category_names
    end

    test "preserves categories with different source" do
      user = insert(:user)
      post = insert(:post, user: user)

      category1 = Repo.get_by(Category, name: "On-chain market analysis")
      category2 = Repo.get_by(Category, name: "Social Trends market analysis")

      # Assign human category
      {:ok, _} = PostCategory.assign_categories(post.id, [category1.id], "human")

      # Assign AI category
      {:ok, _} = PostCategory.assign_categories(post.id, [category2.id], "ai")

      categories = PostCategory.get_post_categories(post.id)
      assert length(categories) == 2

      human_cat = Enum.find(categories, &(&1.category_name == "On-chain market analysis"))
      ai_cat = Enum.find(categories, &(&1.category_name == "Social Trends market analysis"))

      assert human_cat.source == "human"
      assert ai_cat.source == "ai"
    end
  end

  describe "override_with_human_categories/2" do
    test "replaces AI categories with human categories" do
      user = insert(:user)
      post = insert(:post, user: user)

      category1 = Repo.get_by(Category, name: "On-chain market analysis")
      category2 = Repo.get_by(Category, name: "Social Trends market analysis")
      category3 = Repo.get_by(Category, name: "Education on using Santiment")

      # Assign AI categories
      {:ok, _} = PostCategory.assign_categories(post.id, [category1.id, category2.id], "ai")

      # Override with human categories
      {:ok, _} = PostCategory.override_with_human_categories(post.id, [category3.id])

      categories = PostCategory.get_post_categories(post.id)
      assert length(categories) == 1

      assert Enum.at(categories, 0).category_name == "Education on using Santiment"
      assert Enum.at(categories, 0).source == "human"
    end
  end

  describe "has_human_categories?/1" do
    test "returns true when post has human categories" do
      user = insert(:user)
      post = insert(:post, user: user)

      category = Repo.get_by(Category, name: "On-chain market analysis")
      PostCategory.assign_categories(post.id, [category.id], "human")

      assert PostCategory.has_human_categories?(post.id) == true
    end

    test "returns false when post has only AI categories" do
      user = insert(:user)
      post = insert(:post, user: user)

      category = Repo.get_by(Category, name: "On-chain market analysis")
      PostCategory.assign_categories(post.id, [category.id], "ai")

      assert PostCategory.has_human_categories?(post.id) == false
    end

    test "returns false when post has no categories" do
      user = insert(:user)
      post = insert(:post, user: user)

      assert PostCategory.has_human_categories?(post.id) == false
    end
  end

  describe "delete_ai_categories/1" do
    test "deletes only AI categories, preserves human categories" do
      user = insert(:user)
      post = insert(:post, user: user)

      category1 = Repo.get_by(Category, name: "On-chain market analysis")
      category2 = Repo.get_by(Category, name: "Social Trends market analysis")

      PostCategory.assign_categories(post.id, [category1.id], "human")
      PostCategory.assign_categories(post.id, [category2.id], "ai")

      PostCategory.delete_ai_categories(post.id)

      categories = PostCategory.get_post_categories(post.id)
      assert length(categories) == 1
      assert Enum.at(categories, 0).category_name == "On-chain market analysis"
      assert Enum.at(categories, 0).source == "human"
    end
  end
end
