defmodule SanbaseWeb.Graphql.InsightTagOrderTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory
  import Sanbase.TestHelpers

  setup do
    clean_task_supervisor_children()

    Sanbase.Insight.Poll.find_or_insert_current_poll!()
    user = insert(:staked_user)
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  test "tags preserved order in create", %{conn: conn} do
    tags = ["first", "second", "3", "AAA", "XYZ"]
    mutation = create_insight_mutation("Title", "Text", tags)
    result = execute_mutation(conn, mutation)

    assert result["data"]["createInsight"]["tags"] |> Enum.map(& &1["name"]) == tags
  end

  test "tags preserved order in update", %{conn: conn} do
    tags = ["first", "second", "3", "AAA", "XYZ"]
    mutation = create_insight_mutation("Title", "Text", tags)
    result = execute_mutation(conn, mutation)

    id = result["data"]["createInsight"]["id"]

    assert result["data"]["createInsight"]["tags"] |> Enum.map(& &1["name"]) == tags

    mutation2 = update_insight_tags_mutation(id, ["BTC" | tags])
    result2 = execute_mutation(conn, mutation2)

    assert result2["data"]["updateInsight"]["tags"] |> Enum.map(& &1["name"]) == ["BTC" | tags]
  end

  test "tags preserved order after two updates", %{conn: conn} do
    tags = ["first"]
    mutation = create_insight_mutation("Title", "Text", tags)
    result = execute_mutation(conn, mutation)

    id = result["data"]["createInsight"]["id"]

    assert result["data"]["createInsight"]["tags"] |> Enum.map(& &1["name"]) == tags

    tags2 = ["BTC" | tags]
    mutation2 = update_insight_tags_mutation(id, tags2)
    result2 = execute_mutation(conn, mutation2)

    assert result2["data"]["updateInsight"]["tags"] |> Enum.map(& &1["name"]) == tags2

    tags3 = ["SAN", "PESH" | tags]
    mutation3 = update_insight_tags_mutation(id, tags3)
    result3 = execute_mutation(conn, mutation3)

    assert result3["data"]["updateInsight"]["tags"] |> Enum.map(& &1["name"]) == tags3
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
        tags { name }
      }
    }
    """
  end

  defp execute_mutation(conn, query) do
    conn
    |> post("/graphql", mutation_skeleton(query))
    |> json_response(200)
  end
end
