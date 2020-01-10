defmodule SanbaseWeb.Graphql.ProjectApiCombinedStatsTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.InfluxdbHelpers

  alias Sanbase.Prices.Store
  alias Sanbase.Influxdb.Measurement

  setup do
    setup_prices_influxdb()

    p1 = insert(:random_erc20_project)
    p2 = insert(:random_erc20_project)

    measurement1 = Measurement.name_from(p1)
    measurement2 = Measurement.name_from(p2)

    datetime1 = DateTime.from_naive!(~N[2017-05-13 21:45:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-14 21:45:00], "Etc/UTC")
    datetime3 = DateTime.from_naive!(~N[2017-05-15 21:45:00], "Etc/UTC")
    datetime4 = DateTime.from_naive!(~N[2017-05-16 17:30:00], "Etc/UTC")

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
      }
    ])

    [
      from: datetime1,
      to: datetime4,
      slugs: [p1.slug, p2.slug]
    ]
  end

  test "existing slugs and dates", %{conn: conn, from: from, to: to, slugs: slugs} do
    query = query(from, to, slugs)

    result =
      conn
      |> post("/graphql", query_skeleton(query, "projectsListHistoryStats"))
      |> json_response(200)

    assert result == %{
             "data" => %{
               "projectsListHistoryStats" => [
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
                 %{"datetime" => "2017-05-16T00:00:00Z", "marketcap" => 0, "volume" => 0}
               ]
             }
           }
  end

  test "empty slugs", %{conn: conn, from: from, to: to} do
    query = query(from, to, [])

    result =
      conn
      |> post("/graphql", query_skeleton(query, "projectsListHistoryStats"))
      |> json_response(200)

    assert result == %{"data" => %{"projectsListHistoryStats" => []}}
  end

  test "non existing slugs", %{conn: conn, from: from, to: to} do
    query = query(from, to, ["nonexisting", "alsononexisting"])

    result =
      conn
      |> post("/graphql", query_skeleton(query, "projectsListHistoryStats"))
      |> json_response(200)

    assert result == %{"data" => %{"projectsListHistoryStats" => []}}
  end

  test "dates not existing", %{conn: conn, from: from} do
    from_not_existing = Timex.shift(from, days: -30)
    to_not_existing = Timex.shift(from, days: -15)
    query = query(from_not_existing, to_not_existing, ["nonexisting", "alsononexisting"])

    result =
      conn
      |> post("/graphql", query_skeleton(query, "projectsListHistoryStats"))
      |> json_response(200)

    assert result == %{"data" => %{"projectsListHistoryStats" => []}}
  end

  defp query(from, to, slugs) do
    """
    {
      projectsListHistoryStats(
        from: "#{from}",
        to: "#{to}",
        slugs: #{inspect(slugs)},
        interval: "1d") {
          datetime
          marketcap
          volume
        }
    }
    """
  end
end
