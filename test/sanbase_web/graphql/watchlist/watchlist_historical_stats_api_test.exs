defmodule SanbaseWeb.Graphql.WatchlistHistoricalStatsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.TestHelpers

  alias Sanbase.UserList

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    clean_task_supervisor_children()

    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

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
      [datetime4 |> DateTime.to_unix(), 1800, 1300, 1]
    ]

    {:ok, watchlist} = UserList.create_user_list(user, %{name: "test watchlist"})
    {:ok, watchlist2} = UserList.create_user_list(user, %{name: "test watchlist2"})

    {:ok, watchlist} =
      UserList.update_user_list(%{
        id: watchlist.id,
        list_items: [%{project_id: p1.id}, %{project_id: p2.id}]
      })

    %{
      conn: conn,
      user: user,
      watchlist: watchlist,
      from: datetime1,
      to: datetime2,
      empty_watchlist: watchlist2,
      data: data
    }
  end

  test "historical data for watchlists", context do
    %{conn: conn, from: from, to: to, watchlist: watchlist, data: data} = context

    expected_result = %{
      "data" => %{
        "watchlist" => %{
          "historicalStats" => [
            %{
              "datetime" => "2017-05-13T00:00:00Z",
              "marketcap" => 545,
              "volume" => 220
            },
            %{
              "datetime" => "2017-05-14T00:00:00Z",
              "marketcap" => 2000,
              "volume" => 1400
            },
            %{
              "datetime" => "2017-05-15T00:00:00Z",
              "marketcap" => 2600,
              "volume" => 1600
            },
            %{
              "datetime" => "2017-05-16T00:00:00Z",
              "marketcap" => 1800,
              "volume" => 1300
            }
          ]
        }
      }
    }

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: data}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result = get_watchlist_historical_stats(conn, from, to, watchlist)
      assert result == expected_result
    end)
  end

  test "empty watchlist", context do
    %{conn: conn, from: from, to: to, empty_watchlist: watchlist} = context

    result = get_watchlist_historical_stats(conn, from, to, watchlist)

    expected_result = %{"data" => %{"watchlist" => %{"historicalStats" => []}}}
    assert result == expected_result
  end

  test "the database returns an errors", context do
    %{conn: conn, from: from, to: to, watchlist: watchlist} = context

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:error, "Clickhouse error"})
    |> Sanbase.Mock.run_with_mocks(fn ->
      %{"errors" => [error]} = get_watchlist_historical_stats(conn, from, to, watchlist)
      assert error["message"] =~ "Can't fetch historical stats for a watchlist."
    end)
  end

  defp get_watchlist_historical_stats(conn, from, to, watchlist) do
    query = """
      {
      watchlist(id: #{watchlist.id}){
        historicalStats(from: "#{from}", to: "#{to}", interval: "1d") {
          datetime
          marketcap
          volume
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query, "watchlist"))
    |> json_response(200)
  end
end
