defmodule SanbaseWeb.Graphql.InsightTagOrderTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory
  import Sanbase.TestHelpers

  setup do
    clean_task_supervisor_children()

    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  test "tags preserved order in create", %{conn: conn} do
    tags = ["first", "second", "3", "AAA", "XYZ"]
    mutation = create_insight_mutation("Title", "Text", tags)
    result = execute_mutation(conn, mutation)

    assert result["tags"] |> Enum.map(& &1["name"]) == tags
  end

  test "tags preserved order in update", %{conn: conn} do
    tags = ["first", "second", "3", "AAA", "XYZ"]
    mutation = create_insight_mutation("Title", "Text", tags)
    result = execute_mutation(conn, mutation)

    id = result["id"]

    assert result["tags"] |> Enum.map(& &1["name"]) == tags

    tags2 = ["BTC" | tags]
    mutation2 = update_insight_tags_mutation(id, tags2)
    result2 = execute_mutation(conn, mutation2)

    assert result2["tags"] |> Enum.map(& &1["name"]) == tags2
  end

  test "tags preserved order after two updates", %{conn: conn} do
    tags = ["first"]
    mutation = create_insight_mutation("Title", "Text", tags)
    result = execute_mutation(conn, mutation)

    id = result["id"]

    assert result["tags"] |> Enum.map(& &1["name"]) == tags

    tags2 = ["BTC" | tags]
    mutation2 = update_insight_tags_mutation(id, tags2)
    result2 = execute_mutation(conn, mutation2)
    assert result2["tags"] |> Enum.map(& &1["name"]) == tags2

    tags3 = ["SAN", "PESH" | tags]
    mutation3 = update_insight_tags_mutation(id, tags3)
    result3 = execute_mutation(conn, mutation3)
    assert result3["tags"] |> Enum.map(& &1["name"]) == tags3
  end

  test "create tags the first", %{conn: conn} do
    tags = ["first", "second", "third"]

    mutation = create_insight_mutation("Title", "Text", tags)
    result = execute_mutation(conn, mutation)
    id = result["id"]
    assert get_insight_tags(conn, id) == tags

    tags2 = ["third", "first", "BTC", "second"]
    mutation2 = update_insight_tags_mutation(id, tags2)
    execute_mutation(conn, mutation2)
    assert get_insight_tags(conn, id) == ["first", "second", "third", "BTC"]

    tags3 = ["SAN", "PESH" | tags2 |> Enum.reverse()] ++ ["ASD"]
    mutation3 = update_insight_tags_mutation(id, tags3)
    execute_mutation(conn, mutation3)
    assert get_insight_tags(conn, id) == ["first", "second", "third", "BTC", "SAN", "PESH", "ASD"]
  end

  defp create_insight_mutation(title, text, tags) do
    """
    mutation {
      createInsight(title: "#{title}", text: "#{text}", tags: #{inspect(tags)}) {
        id
        tags { name }
      }
    }
    """
  end

  defp update_insight_tags_mutation(id, tags) do
    """
    mutation {
      updateInsight(id: #{id}, tags: #{inspect(tags)}) {
        id
        tags { name }
      }
    }
    """
  end

  defp get_insight_tags(conn, id) do
    query = """
    {
      insight(id: #{id}) {
        id
        tags { name }
      }
    }
    """

    execute_query(conn, query)
    |> get_in(["data", "insight", "tags"])
    |> Enum.map(& &1["name"])
  end

  defp execute_query(conn, query) do
    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
