defmodule SanbaseWeb.Graphql.ProjectApiAvailableFoundersTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    %{
      p1: insert(:project, slug: "bitcoin"),
      p2: insert(:project, slug: "ethereum")
    }
  end

  test "fetch aggregated timeseries data projects", context do
    rows = [
      ["Satoshi Nacamoto", "bitcoin"],
      ["Vitalik Buterin", "ethereum"]
    ]

    Sanbase.Mock.prepare_mock2(
      &Sanbase.ClickhouseRepo.query/2,
      {:ok, %{rows: rows}}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        execute(context.conn)
        |> get_in(["data", "allProjects"])

      assert length(result) == 2
      assert %{"availableFounders" => ["Satoshi Nacamoto"], "slug" => "bitcoin"} in result
      assert %{"availableFounders" => ["Vitalik Buterin"], "slug" => "ethereum"} in result
    end)
  end

  defp execute(conn) do
    query = """
    {
      allProjects {
        slug
        availableFounders
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
