defmodule SanbaseWeb.Graphql.PricesApiTest do
  use SanbaseWeb.ConnCase
  use Phoenix.ConnTest

  alias SanbaseWeb.Graphql.{PriceResolver, PriceTypes}
  alias Sanbase.Prices.{Store, Measurement}

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

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "historyPrice"))

    assert json_response(result, 200)["data"]["historyPrice"] == []
  end

  test "fetch current price for a ticker", context do
    Store.drop_pair("TEST_BTC")
    Store.drop_pair("TEST_USD")

    Store.import([
      # older
      %Measurement{
        timestamp:
          Sanbase.DateTimeUtils.seconds_ago(60 * 60 * 24) |> DateTime.to_unix(:nanoseconds),
        fields: %{price: 2220, volume: 5220, marketcap: 22500},
        name: "TEST_BTC"
      },
      %Measurement{
        timestamp:
          Sanbase.DateTimeUtils.seconds_ago(60 * 60 * 24) |> DateTime.to_unix(:nanoseconds),
        fields: %{price: 2222, volume: 2225, marketcap: 22250},
        name: "TEST_USD"
      },
      # newer
      %Measurement{
        timestamp: DateTime.utc_now() |> DateTime.to_unix(:nanoseconds),
        fields: %{price: 20, volume: 50, marketcap: 500},
        name: "TEST_BTC"
      },
      %Measurement{
        timestamp: DateTime.utc_now() |> DateTime.to_unix(:nanoseconds),
        fields: %{price: 2, volume: 5, marketcap: 50},
        name: "TEST_USD"
      }
    ])

    query = """
    {
      price(ticker: "TEST") {
        priceUsd
        priceBtc
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "price"))

    assert json_response(result, 200)["data"]["price"]["priceUsd"] == "2"
    assert json_response(result, 200)["data"]["price"]["priceBtc"] == "20"
  end
end