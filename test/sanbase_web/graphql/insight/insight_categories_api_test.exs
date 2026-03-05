defmodule SanbaseWeb.Graphql.InsightCategoriesApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  alias Sanbase.Insight.{Category, PostCategory}

  setup do
    _role = insert(:role_san_family)

    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    # Create categories
    {:ok, cat1} =
      %Category{} |> Category.changeset(%{name: "Technical Analysis"}) |> Sanbase.Repo.insert()

    {:ok, cat2} =
      %Category{} |> Category.changeset(%{name: "Market Overview"}) |> Sanbase.Repo.insert()

    {:ok, cat3} =
      %Category{} |> Category.changeset(%{name: "On-Chain Analysis"}) |> Sanbase.Repo.insert()

    {:ok, conn: conn, user: user, cat1: cat1, cat2: cat2, cat3: cat3}
  end

  defp seconds_ago(seconds) do
    Timex.shift(DateTime.utc_now(), seconds: -seconds)
  end

  describe "allInsightCategories" do
    test "returns all categories with insight counts", context do
      %{conn: conn, cat1: cat1, cat2: cat2} = context

      i1 = insert(:published_post, published_at: seconds_ago(30))
      i2 = insert(:published_post, published_at: seconds_ago(20))
      _draft = insert(:post, ready_state: "draft")

      PostCategory.assign_categories(i1.id, [cat1.id, cat2.id], "ai")
      PostCategory.assign_categories(i2.id, [cat1.id], "human")

      result = all_insight_categories(conn)
      assert length(result) == 3

      ta = Enum.find(result, &(&1["name"] == "Technical Analysis"))
      mo = Enum.find(result, &(&1["name"] == "Market Overview"))
      oc = Enum.find(result, &(&1["name"] == "On-Chain Analysis"))

      assert ta["insightsCount"] == 2
      assert mo["insightsCount"] == 1
      assert oc["insightsCount"] == 0
    end

    test "does not count draft or unapproved insights", context do
      %{conn: conn, cat1: cat1} = context

      draft = insert(:post, ready_state: "draft")
      declined = insert(:post, ready_state: "published", state: "declined")
      deleted = insert(:published_post, is_deleted: true, published_at: seconds_ago(10))

      PostCategory.assign_categories(draft.id, [cat1.id], "ai")
      PostCategory.assign_categories(declined.id, [cat1.id], "ai")
      PostCategory.assign_categories(deleted.id, [cat1.id], "ai")

      result = all_insight_categories(conn)
      ta = Enum.find(result, &(&1["name"] == "Technical Analysis"))
      assert ta["insightsCount"] == 0
    end
  end

  describe "categories field on insight" do
    test "returns categories for an insight", context do
      %{conn: conn, cat1: cat1, cat2: cat2} = context

      insight = insert(:published_post, published_at: seconds_ago(10))
      PostCategory.assign_categories(insight.id, [cat1.id, cat2.id], "ai")

      result = get_insight_with_categories(conn, insight.id)
      categories = result["categories"]

      assert length(categories) == 2
      names = Enum.map(categories, & &1["name"])
      assert "Technical Analysis" in names
      assert "Market Overview" in names
    end

    test "returns empty list when insight has no categories", context do
      %{conn: conn} = context

      insight = insert(:published_post, published_at: seconds_ago(10))

      result = get_insight_with_categories(conn, insight.id)
      assert result["categories"] == []
    end
  end

  describe "allInsights with categories filter" do
    test "filters insights by category", context do
      %{conn: conn, cat1: cat1, cat2: cat2} = context

      i1 = insert(:published_post, published_at: seconds_ago(30), title: "Insight 1")
      i2 = insert(:published_post, published_at: seconds_ago(20), title: "Insight 2")
      _i3 = insert(:published_post, published_at: seconds_ago(10), title: "Insight 3")

      PostCategory.assign_categories(i1.id, [cat1.id], "ai")
      PostCategory.assign_categories(i2.id, [cat1.id, cat2.id], "human")

      result = all_insights_with_categories(conn, ["Technical Analysis"])
      assert length(result) == 2
      ids = Enum.map(result, & &1["id"])
      assert i1.id in ids
      assert i2.id in ids
    end

    test "filters by multiple categories (OR)", context do
      %{conn: conn, cat1: cat1, cat2: cat2, cat3: cat3} = context

      i1 = insert(:published_post, published_at: seconds_ago(30), title: "Insight 1")
      i2 = insert(:published_post, published_at: seconds_ago(20), title: "Insight 2")
      i3 = insert(:published_post, published_at: seconds_ago(10), title: "Insight 3")

      PostCategory.assign_categories(i1.id, [cat1.id], "ai")
      PostCategory.assign_categories(i2.id, [cat2.id], "ai")
      PostCategory.assign_categories(i3.id, [cat3.id], "ai")

      result = all_insights_with_categories(conn, ["Technical Analysis", "Market Overview"])
      assert length(result) == 2
      ids = Enum.map(result, & &1["id"])
      assert i1.id in ids
      assert i2.id in ids
    end

    test "returns empty list when no insights match category", context do
      %{conn: conn} = context

      _i1 = insert(:published_post, published_at: seconds_ago(10), title: "Insight 1")

      result = all_insights_with_categories(conn, ["Technical Analysis"])
      assert result == []
    end
  end

  describe "getMostRecent with categories filter" do
    test "filters insights by category in entity query", context do
      %{conn: conn, cat1: cat1, cat2: cat2} = context

      i1 = insert(:published_post, published_at: seconds_ago(30))
      i2 = insert(:published_post, published_at: seconds_ago(20))
      _i3 = insert(:published_post, published_at: seconds_ago(10))

      PostCategory.assign_categories(i1.id, [cat1.id], "ai")
      PostCategory.assign_categories(i2.id, [cat2.id], "human")

      result =
        get_most_recent(conn, [:insight],
          filter: %{
            map_as_input_object: true,
            insight: %{
              map_as_input_object: true,
              categories: ["Technical Analysis"]
            }
          }
        )

      data = result["data"]
      stats = result["stats"]

      assert stats["totalEntitiesCount"] == 1
      assert length(data) == 1
      assert hd(data)["insight"]["id"] == i1.id
    end

    test "categories filter combined with paywall filter", context do
      %{conn: conn, cat1: cat1} = context

      i1 =
        insert(:published_post,
          published_at: seconds_ago(30),
          is_paywall_required: true
        )

      i2 =
        insert(:published_post,
          published_at: seconds_ago(20),
          is_paywall_required: false
        )

      PostCategory.assign_categories(i1.id, [cat1.id], "ai")
      PostCategory.assign_categories(i2.id, [cat1.id], "ai")

      result =
        get_most_recent(conn, [:insight],
          filter: %{
            map_as_input_object: true,
            insight: %{
              map_as_input_object: true,
              categories: ["Technical Analysis"],
              paywall: :paywalled_only
            }
          }
        )

      data = result["data"]
      assert length(data) == 1
      assert hd(data)["insight"]["id"] == i1.id
    end
  end

  describe "getMostVoted with categories filter" do
    test "filters insights by category in most voted query", context do
      %{conn: conn, cat1: cat1} = context

      i1 = insert(:published_post, published_at: seconds_ago(30))
      i2 = insert(:published_post, published_at: seconds_ago(20))

      PostCategory.assign_categories(i1.id, [cat1.id], "ai")

      vote(conn, i1.id)
      vote(conn, i2.id)

      result =
        get_most_voted(conn, [:insight],
          filter: %{
            map_as_input_object: true,
            insight: %{
              map_as_input_object: true,
              categories: ["Technical Analysis"]
            }
          }
        )

      data = result["data"]
      assert length(data) == 1
      assert hd(data)["insight"]["id"] == i1.id
    end
  end

  # Helper functions

  defp all_insight_categories(conn) do
    query = """
    {
      allInsightCategories {
        name
        description
        insightsCount
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "allInsightCategories"])
  end

  defp get_insight_with_categories(conn, id) do
    query = """
    {
      insight(id: #{id}) {
        id
        categories {
          name
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "insight"])
  end

  defp all_insights_with_categories(conn, categories) do
    categories_str = Enum.map(categories, &"\"#{&1}\"") |> Enum.join(", ")

    query = """
    {
      allInsights(categories: [#{categories_str}]) {
        id
        title
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "allInsights"])
  end

  defp get_most_recent(conn, entity_or_entities, opts) do
    opts =
      opts
      |> Keyword.put_new(:page, 1)
      |> Keyword.put_new(:page_size, 10)
      |> Keyword.put_new(:types, List.wrap(entity_or_entities))
      |> Keyword.put_new(:min_title_length, 0)
      |> Keyword.put_new(:min_description_length, 0)

    args =
      case Map.new(opts) do
        %{filter: _} = map -> put_in(map, [:filter, :map_as_input_object], true)
        map -> map
      end

    query =
      """
      {
        getMostRecent(#{map_to_args(args)}){
          stats { currentPage currentPageSize totalPagesCount totalEntitiesCount }
          data {
            insight{ id }
          }
        }
      }
      """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "getMostRecent"])
  end

  defp get_most_voted(conn, entity_or_entities, opts) do
    opts =
      opts
      |> Keyword.put_new(:page, 1)
      |> Keyword.put_new(:page_size, 10)
      |> Keyword.put_new(:types, List.wrap(entity_or_entities))
      |> Keyword.put_new(:min_title_length, 0)
      |> Keyword.put_new(:min_description_length, 0)

    args =
      case Map.new(opts) do
        %{filter: _} = map -> put_in(map, [:filter, :map_as_input_object], true)
        map -> map
      end

    query =
      """
      {
        getMostVoted(#{map_to_args(args)}){
          stats { currentPage currentPageSize totalPagesCount totalEntitiesCount }
          data {
            insight{ id }
          }
        }
      }
      """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "getMostVoted"])
  end

  defp vote(conn, insight_id) do
    mutation = """
    mutation {
      vote(insightId: #{insight_id}) {
        votes{ totalVotes }
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end
end
