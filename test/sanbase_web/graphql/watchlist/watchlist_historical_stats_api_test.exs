defmodule SanbaseWeb.Graphql.WatchlistHistoricalStatsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.TestHelpers

  alias Sanbase.UserList
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Prices.Store

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.InfluxdbHelpers
  import Sanbase.Factory

  setup do
    setup_prices_influxdb()

    clean_task_supervisor_children()

    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    p1 = insert(:random_erc20_project)
    p2 = insert(:random_erc20_project)

    %{from: from, to: to} = setup_db(p1, p2)

    {:ok, watchlist} = UserList.create_user_list(user, %{name: "test watchlist"})
    {:ok, watchlist2} = UserList.create_user_list(user, %{name: "test watchlist2"})

    {:ok, watchlist} =
      UserList.update_user_list(%{
        id: watchlist.id,
        list_items: [%{project_id: p1.id}, %{project_id: p2.id}]
      })

    {:ok,
     conn: conn, user: user, watchlist: watchlist, from: from, to: to, empty_watchlist: watchlist2}
  end

  test "historical data for watchlists", context do
    query = """
    {
      watchlist(id: #{context.watchlist.id}){
        historicalStats(from: "#{context.from}", to: "#{context.to}", interval: "1d") {
          datetime
          marketcap
          volume
        }
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "watchlist"))
      |> json_response(200)

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

    assert result == expected_result
  end

  test "historical data for watchlists with no  projects", context do
    query = """
    {
      watchlist(id: #{context.empty_watchlist.id}){
        historicalStats(from: "#{context.from}", to: "#{context.to}", interval: "1d") {
          datetime
          marketcap
          volume
        }
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "watchlist"))
      |> json_response(200)

    expected_result = %{
      "data" => %{
        "watchlist" => %{
          "historicalStats" => []
        }
      }
    }

    assert result == expected_result
  end

  def setup_db(p1, p2) do
    measurement1 = Measurement.name_from(p1)
    measurement2 = Measurement.name_from(p2)

    datetime1 = DateTime.from_naive!(~N[2017-05-13 21:45:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-14 21:45:00], "Etc/UTC")
    datetime3 = DateTime.from_naive!(~N[2017-05-15 21:45:00], "Etc/UTC")
    datetime4 = DateTime.from_naive!(~N[2017-05-16 21:45:00], "Etc/UTC")
    datetime5 = DateTime.from_naive!(~N[2017-05-16 23:59:59], "Etc/UTC")

    Store.import([
      %Measurement{
        timestamp: datetime1 |> DateTime.to_unix(:nanosecond),
        fields: %{price_usd: 25, price_btc: 1, volume_usd: 220, marketcap_usd: 545},
        name: measurement1
      },
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanosecond),
        fields: %{price_usd: 20, price_btc: 1000, volume_usd: 200, marketcap_usd: 500},
        name: measurement1
      },
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanosecond),
        fields: %{price_usd: 22, price_btc: 1200, volume_usd: 300, marketcap_usd: 800},
        name: measurement1
      },
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanosecond),
        fields: %{price_usd: 20, price_btc: 1, volume_usd: 5, marketcap_usd: 500},
        name: measurement2
      },
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanosecond),
        fields: %{volume_usd: 1200, marketcap_usd: 1500},
        name: measurement2
      },
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanosecond),
        fields: %{volume_usd: 1300, marketcap_usd: 1800},
        name: measurement2
      },
      %Measurement{
        timestamp: datetime4 |> DateTime.to_unix(:nanosecond),
        fields: %{volume_usd: 1300, marketcap_usd: 1800},
        name: measurement2
      }
    ])

    %{from: datetime1, to: datetime5}
  end
end
