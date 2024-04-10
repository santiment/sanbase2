defmodule SanbaseWeb.Graphql.EcosystemsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    eth_ecosystem = insert(:ecosystem, ecosystem: "ethereum")
    btc_ecosystem = insert(:ecosystem, ecosystem: "bitcoin")

    p1 = insert(:random_erc20_project)
    p2 = insert(:random_erc20_project)
    p3 = insert(:random_erc20_project)

    %{
      conn: conn,
      user: user,
      eth_ecosystem: eth_ecosystem,
      btc_ecosystem: btc_ecosystem,
      p1: p1,
      p2: p2,
      p3: p3
    }
  end

  test "get the projects in an ecosystem", context do
    data =
      get_ecosystems_with_projects(context.conn, [
        context.eth_ecosystem.ecosystem,
        context.btc_ecosystem.ecosystem
      ])
      |> get_in(["data", "getEcosystems"])

    assert data == []
  end

  defp get_ecosystems_projects(conn, ecosystems) do
    query = """
    {
      ecosystems(#{map_to_args(%{ecosystems: ecosystems})}){
        name
        projects { slug }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp get_ecosystems_timeseries_data(conn, ecosystems, args) do
    query = """
        {
          ecosystems(#{map_to_args(%{ecosystems: ecosystems})}){
            name
            projects { slug }
          }
        }
    """
  end
end
