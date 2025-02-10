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
      context.conn
      |> get_ecosystems_projects([
        "ethereum",
        "bitcoin"
      ])
      |> get_in(["data", "getEcosystems"])

    assert %{"name" => "ethereum", "projects" => []} in data
    assert %{"name" => "bitcoin", "projects" => []} in data

    {:ok, _} = Sanbase.ProjectEcosystemMapping.create(context.p1.id, context.eth_ecosystem.id)
    {:ok, _} = Sanbase.ProjectEcosystemMapping.create(context.p2.id, context.eth_ecosystem.id)
    {:ok, _} = Sanbase.ProjectEcosystemMapping.create(context.p1.id, context.btc_ecosystem.id)

    data =
      context.conn
      |> get_ecosystems_projects(["ethereum", "bitcoin"])
      |> get_in(["data", "getEcosystems"])

    eth_ecosystem = Enum.find(data, &(&1["name"] == "ethereum"))
    # Make it so the order of the projects does not matter
    assert %{"slug" => context.p2.slug} in eth_ecosystem["projects"]
    assert %{"slug" => context.p1.slug} in eth_ecosystem["projects"]

    assert %{
             "name" => "bitcoin",
             "projects" => [%{"slug" => context.p1.slug}]
           } in data
  end

  test "get timeseries data", context do
    {:ok, _} = Sanbase.ProjectEcosystemMapping.create(context.p1.id, context.eth_ecosystem.id)
    {:ok, _} = Sanbase.ProjectEcosystemMapping.create(context.p2.id, context.eth_ecosystem.id)

    rows = [
      ["ethereum", 1_712_620_800, 7433.0],
      ["ethereum", 1_712_707_200, 6783.0],
      ["ethereum", 1_712_793_600, 1126.0]
    ]

    (&Sanbase.ClickhouseRepo.query/2)
    |> Sanbase.Mock.prepare_mock2({:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      data =
        context.conn
        |> get_ecosystems_timeseries_data(["ethereum"], %{
          from: ~U[2024-04-08 00:00:00Z],
          to: ~U[2024-04-11 00:00:00Z],
          interval: "1d",
          metric: "ecosystem_dev_activity"
        })
        |> get_in(["data", "getEcosystems"])

      assert data ==
               [
                 %{
                   "name" => "ethereum",
                   "timeseriesData" => [
                     %{"datetime" => "2024-04-09T00:00:00Z", "value" => 7433.0},
                     %{"datetime" => "2024-04-10T00:00:00Z", "value" => 6783.0},
                     %{"datetime" => "2024-04-11T00:00:00Z", "value" => 1126.0}
                   ]
                 }
               ]
    end)
  end

  test "get timeseries data with transform", context do
    {:ok, _} = Sanbase.ProjectEcosystemMapping.create(context.p1.id, context.eth_ecosystem.id)
    {:ok, _} = Sanbase.ProjectEcosystemMapping.create(context.p2.id, context.eth_ecosystem.id)

    rows = [
      ["ethereum", 1_712_361_600, 1100.0],
      ["ethereum", 1_712_448_000, 1289.0],
      ["ethereum", 1_712_534_400, 7147.0],
      ["ethereum", 1_712_620_800, 7433.0],
      ["ethereum", 1_712_707_200, 6783.0],
      ["ethereum", 1_712_793_600, 1126.0]
    ]

    (&Sanbase.ClickhouseRepo.query/2)
    |> Sanbase.Mock.prepare_mock2({:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      data =
        context.conn
        |> get_ecosystems_timeseries_data(["ethereum"], %{
          from: ~U[2024-04-08 00:00:00Z],
          to: ~U[2024-04-11 00:00:00Z],
          interval: "1d",
          metric: "ecosystem_dev_activity",
          transform: %{type: "moving_average", moving_average_base: 3, map_as_input_object: true}
        })
        |> get_in(["data", "getEcosystems"])

      assert data == [
               %{
                 "name" => "ethereum",
                 "timeseriesData" => [
                   %{"datetime" => "2024-04-08T00:00:00Z", "value" => 3178.67},
                   %{"datetime" => "2024-04-09T00:00:00Z", "value" => 5289.67},
                   %{"datetime" => "2024-04-10T00:00:00Z", "value" => 7121.0},
                   %{"datetime" => "2024-04-11T00:00:00Z", "value" => 5114.0}
                 ]
               }
             ]
    end)
  end

  test "get aggregated timeseries data", context do
    {:ok, _} = Sanbase.ProjectEcosystemMapping.create(context.p1.id, context.eth_ecosystem.id)
    {:ok, _} = Sanbase.ProjectEcosystemMapping.create(context.p2.id, context.eth_ecosystem.id)

    rows = [
      ["ethereum", 1100.1],
      ["bitcoin", 1212.4]
    ]

    (&Sanbase.ClickhouseRepo.query/2)
    |> Sanbase.Mock.prepare_mock2({:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      data =
        context.conn
        |> get_ecosystems_aggregated_timeseries_data(
          ["ethereum", "bitcoin"],
          %{
            from: ~U[2024-04-08 00:00:00Z],
            to: ~U[2024-04-11 00:00:00Z],
            metric: "ecosystem_github_activity"
          }
        )
        |> get_in(["data", "getEcosystems"])

      assert %{
               "name" => "ethereum",
               "aggregatedTimeseriesData" => 1100.1
             } in data

      assert %{
               "name" => "bitcoin",
               "aggregatedTimeseriesData" => 1212.4
             } in data
    end)
  end

  defp get_ecosystems_projects(conn, ecosystems) do
    query = """
    {
      getEcosystems(#{map_to_args(%{ecosystems: ecosystems})}){
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
    query =
      """
          {
            getEcosystems(#{map_to_args(%{ecosystems: ecosystems})}){
              name
              timeseriesData(#{map_to_args(args)}) {
                datetime
                value
              }
            }
          }
      """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp get_ecosystems_aggregated_timeseries_data(conn, ecosystems, args) do
    query =
      """
      {
        getEcosystems(#{map_to_args(%{ecosystems: ecosystems})}){
          name
          aggregatedTimeseriesData(#{map_to_args(args)})
        }
      }
      """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
