defmodule SanbaseWeb.Graphql.ProjectApiCombinedStatsTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.InfluxdbHelpers

  require Sanbase.Mock

  setup do
    setup_prices_influxdb()

    p1 = insert(:random_erc20_project)
    p2 = insert(:random_erc20_project)

    datetime1 = ~U[2017-05-13 00:00:00Z]
    datetime2 = ~U[2017-05-14 00:00:00Z]
    datetime3 = ~U[2017-05-15 00:00:00Z]
    datetime4 = ~U[2017-05-16 00:00:00Z]

    data = [
      [datetime1 |> DateTime.to_unix(), 545, 220, 1],
      [datetime2 |> DateTime.to_unix(), 2000, 1400, 1],
      [datetime3 |> DateTime.to_unix(), 2600, 1600, 1],
      [datetime4 |> DateTime.to_unix(), 0, 0, 0]
    ]

    %{from: datetime1, to: datetime4, slugs: [p1.slug, p2.slug], data: data}
  end

  test "existing slugs and dates", context do
    %{conn: conn, from: from, to: to, slugs: slugs, data: data} = context

    fn ->
      result = get_history_stats(conn, from, to, slugs)

      Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: data}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert result == %{
                 "data" => %{
                   "projectsListHistoryStats" => [
                     %{"datetime" => "2017-05-13T00:00:00Z", "marketcap" => 545, "volume" => 220},
                     %{
                       "datetime" => "2017-05-14T00:00:00Z",
                       "marketcap" => 2000,
                       "volume" => 1400
                     },
                     %{
                       "datetime" => "2017-05-15T00:00:00Z",
                       "marketcap" => 2600,
                       "volume" => 1600
                     }
                   ]
                 }
               }
      end)
    end
  end

  test "the database returns no data", context do
    %{conn: conn, from: from, to: to, slugs: slugs} = context

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: []}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result = get_history_stats(conn, from, to, slugs)
      assert result == %{"data" => %{"projectsListHistoryStats" => []}}
    end)
  end

  test "the database returns an error", context do
    %{conn: conn, from: from, to: to, slugs: slugs} = context

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:error, "Database error"})
    |> Sanbase.Mock.run_with_mocks(fn ->
      %{"errors" => [error]} = get_history_stats(conn, from, to, slugs)
      assert error["message"] =~ "Cannot get combined history stats for a list of slugs."
    end)
  end

  defp get_history_stats(conn, from, to, slugs) do
    query = """
    {
      projectsListHistoryStats(
        from: "#{from}"
        to: "#{to}"
        slugs: #{inspect(slugs)}
        interval: "1d") {
          datetime
          marketcap
          volume
        }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query, "projectsListHistoryStats"))
    |> json_response(200)
  end
end
