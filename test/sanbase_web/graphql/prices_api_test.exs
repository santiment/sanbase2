defmodule SanbaseWeb.Graphql.PricesApiTest do
  use SanbaseWeb.ConnCase
  use Phoenix.ConnTest

  alias SanbaseWeb.Graphql.{PriceResolver, PriceTypes}
  alias Sanbase.Prices.Store
  alias Sanbase.Influxdb.Measurement

  import Plug.Conn
  import ExUnit.CaptureLog

  defp query_skeleton(query, query_name) do
    %{
      "operationName" => "#{query_name}",
      "query" => "query #{query_name} #{query}",
      "variables" => "{}"
    }
  end

  setup do
    Application.fetch_env!(:sanbase, Sanbase.Prices.Store)
    |> Keyword.get(:database)
    |> Instream.Admin.Database.create()
    |> Store.execute()

    Store.drop_pair("TEST_BTC")
    Store.drop_pair("TEST_USD")

    now = DateTime.utc_now() |> DateTime.to_unix(:nanoseconds)
    yesterday = Sanbase.DateTimeUtils.seconds_ago(60 * 60 * 24) |> DateTime.to_unix(:nanoseconds)

    Store.import([
      # older
      %Measurement{
        timestamp: yesterday,
        fields: %{price: 1000, volume: 200, marketcap: 500},
        name: "TEST_BTC"
      },
      %Measurement{
        timestamp: yesterday,
        fields: %{price: 20, volume: 200, marketcap: 500},
        name: "TEST_USD"
      },
      # newer
      %Measurement{
        timestamp: now,
        fields: %{price: 1200, volume: 300, marketcap: 800},
        name: "TEST_BTC"
      },
      %Measurement{
        timestamp: now,
        fields: %{price: 22, volume: 300, marketcap: 800},
        name: "TEST_USD"
      }
    ])

    :ok
  end

  test "no information is available for a ticker", context do
    Store.drop_pair("SAN_USD")

    now = DateTime.utc_now()
    yesterday = Sanbase.DateTimeUtils.seconds_ago(60 * 60 * 24)

    query = """
    {
      historyPrice(ticker: "SAN", from: "#{yesterday}", to: "#{now}", interval: "1h") {
        datetime
        priceUsd
      }
    }
    """

    result = context.conn
    |> post("/graphql", query_skeleton(query, "historyPrice"))

    assert json_response(result, 200)["data"]["historyPrice"] == []
  end

  test "fetch current price for a ticker", context do
    query = """
    {
      price(ticker: "TEST") {
        priceUsd
        priceBtc
      }
    }
    """

    result = context.conn
    |> post("/graphql", query_skeleton(query, "price"))

    assert json_response(result, 200)["data"]["price"]["priceUsd"] == "22"
    assert json_response(result, 200)["data"]["price"]["priceBtc"] == "1200"
    IO.inspect(json_response(result, 200))

  end

  test "data aggregation for larger intervals", context do
    now = DateTime.utc_now()
    two_days_ago = Sanbase.DateTimeUtils.seconds_ago(2 * 60 * 60 * 24)

    query = """
    {
      historyPrice(ticker: "TEST", from: "#{two_days_ago}", to: "#{now}", interval: "1w") {
        priceUsd
        priceBtc
        marketcap
        volume
      }
    }
    """

    result = context.conn
    |> post("/graphql", query_skeleton(query, "historyPrice"))

    history_price = json_response(result, 200)["data"]["historyPrice"]
    assert Enum.count(history_price) == 1

    [history_price|_] = history_price
    assert history_price["priceUsd"] == "21"
    assert history_price["priceBtc"] == "1100"
    assert history_price["volume"] == "500"
    assert history_price["marketcap"] == "650"
  end
end