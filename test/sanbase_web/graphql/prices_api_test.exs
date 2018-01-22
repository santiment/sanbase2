defmodule SanbaseWeb.Graphql.PricesApiTest do
  use SanbaseWeb.ConnCase
  use Phoenix.ConnTest

  alias Sanbase.Prices.Store
  alias Sanbase.Influxdb.Measurement

  import Plug.Conn
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    Application.fetch_env!(:sanbase, Sanbase.Prices.Store)
    |> Keyword.get(:database)
    |> Instream.Admin.Database.create()
    |> Store.execute()

    Store.drop_measurement("TEST_BTC")
    Store.drop_measurement("TEST_USD")
    Store.drop_measurement("XYZ_USD")
    Store.drop_measurement("XYZ_BTC")

    datetime1 = DateTime.from_naive!(~N[2017-05-13 21:45:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-14 21:45:00], "Etc/UTC")
    datetime3 = DateTime.from_naive!(~N[2017-05-15 21:45:00], "Etc/UTC")
    years_ago = DateTime.from_naive!(~N[2007-01-01 21:45:00], "Etc/UTC")

    Store.import([
      # older
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanoseconds),
        fields: %{price: 1000, volume: 200, marketcap: 500},
        name: "TEST_BTC"
      },
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanoseconds),
        fields: %{price: 20, volume: 200, marketcap: 500},
        name: "TEST_USD"
      },
      # newer
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanoseconds),
        fields: %{price: 1200, volume: 300, marketcap: 800},
        name: "TEST_BTC"
      },
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanoseconds),
        fields: %{price: 22, volume: 300, marketcap: 800},
        name: "TEST_USD"
      },
      # older
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanoseconds),
        fields: %{price: 1, volume: 5, marketcap: 500},
        name: "XYZ_BTC"
      },
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanoseconds),
        fields: %{price: 20, volume: 200, marketcap: 500},
        name: "XYZ_USD"
      }
    ])

    [
      datetime1: datetime1,
      datetime2: datetime2,
      datetime3: datetime3,
      years_ago: years_ago
    ]
  end

  test "no information is available for a ticker", context do
    Store.drop_measurement("SAN_USD")
    query = """
    {
      historyPrice(ticker: "SAN", from: "#{context.datetime1}", to: "#{context.datetime2}", interval: "1h") {
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

    assert json_response(result, 200)["data"]["price"]["priceUsd"] == "22"
    assert json_response(result, 200)["data"]["price"]["priceBtc"] == "1200"
  end

  test "data aggregation for larger intervals", context do
    query = """
    {
      historyPrice(ticker: "TEST", from: "#{context.datetime1}", to: "#{context.datetime3}", interval: "2d") {
        datetime
        priceUsd
        priceBtc
        marketcap
        volume
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "historyPrice"))

    history_price = json_response(result, 200)["data"]["historyPrice"]
    assert Enum.count(history_price) == 1

    [history_price | _] = history_price
    assert history_price["priceUsd"] == "21"
    assert history_price["priceBtc"] == "1100"
    assert history_price["volume"] == "300"
    assert history_price["marketcap"] == "650"
  end

  test "too complex queries are denied", context do
    query = """
    {
      historyPrice(ticker: "TEST", from: "#{context.years_ago}", to: "#{context.datetime1}", interval: "5m"){
        priceUsd
        priceBtc
        datetime
        volume
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "historyPrice"))

    [error | _] = json_response(result, 400)["errors"]
    assert String.contains?(error["message"], "too complex")
  end

  test "default arguments are correctly set", context do
    query = """
    {
      historyPrice(ticker: "TEST", from: "#{context.datetime1}"){
        priceUsd
      }
    }
    """

    result =
      context.conn
      |> put_req_header("authorization", "Basic " <> basic_auth())
      |> post("/graphql", query_skeleton(query, "historyPrice"))

    history_price = json_response(result, 200)["data"]["historyPrice"]
    assert Enum.count(history_price) == 2
    assert Enum.at(history_price, 0)["priceUsd"] == "20"
    assert Enum.at(history_price, 1)["priceUsd"] == "22"
  end

  test "complexity is 0 with basic authentication", context do
    query = """
    {
      historyPrice(ticker: "TEST", from: "#{context.years_ago}", to: "#{context.datetime1}", interval: "5m"){
        priceUsd
        priceBtc
        datetime
        volume
      }
    }
    """

    result =
      context.conn
      |> put_req_header("authorization", "Basic " <> basic_auth())
      |> post("/graphql", query_skeleton(query, "historyPrice"))

    assert json_response(result, 200)["data"] != nil
  end

  test "fetch all available prices", context do
    query = """
    {
      availablePrices
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "availablePrices"))

    resp_data = json_response(result,200)["data"]["availablePrices"]
    assert Enum.count(resp_data) == 2
    assert "TEST" in resp_data
    assert "XYZ" in resp_data
  end

  test "fetch price for a list of tickers", context do
    query = """
    {
      prices(tickers: ["TEST", "XYZ"]){
        ticker
        priceUsd
        priceBtc
      }
    }
    """

    result =
      context.conn
      |> put_req_header("authorization", "Basic " <> basic_auth())
      |> post("/graphql", query_skeleton(query, "prices"))

    resp_data = json_response(result, 200)["data"]["prices"]

    assert %{"priceBtc" => "1200", "priceUsd" => "22", "ticker" => "TEST"} in resp_data
    assert %{"priceBtc" => "1", "priceUsd" => "20", "ticker" => "XYZ"} in resp_data
  end

  defp basic_auth() do
    username =
      Application.fetch_env!(:sanbase, SanbaseWeb.Graphql.ContextPlug)
      |> Keyword.get(:basic_auth_username)

    password =
      Application.fetch_env!(:sanbase, SanbaseWeb.Graphql.ContextPlug)
      |> Keyword.get(:basic_auth_password)

    Base.encode64(username <> ":" <> password)
  end
end