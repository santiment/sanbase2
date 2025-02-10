defmodule Sanbase.Project.InfoTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  test "get project's available metrics", context do
    insert(:project, slug: "bitcoin")
    insert(:project, slug: "ethereum")

    rows = [
      ["bitcoin", "bitcoin full info", "short btc info"],
      ["ethereum", "ethereum full info", "short eth info"]
    ]

    (&Sanbase.ClickhouseRepo.query/2)
    |> Sanbase.Mock.prepare_mock2({:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result = context.conn |> get_projects_info() |> get_in(["data", "allProjects"])
      assert length(result) == 2

      assert %{
               "info" => %{"full" => "bitcoin full info", "summary" => "short btc info"},
               "slug" => "bitcoin"
             } in result

      assert %{
               "info" => %{"full" => "ethereum full info", "summary" => "short eth info"},
               "slug" => "ethereum"
             } in result
    end)
  end

  defp get_projects_info(conn) do
    query = """
    {
      allProjects{
        slug
        info {
          full
          summary
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
