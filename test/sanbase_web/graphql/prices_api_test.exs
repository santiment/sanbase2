defmodule SanbaseWeb.Graphql.PricesApiTest do
  use SanbaseWeb.ConnCase
  use Phoenix.ConnTest

  alias Sanbase.Prices.Store
  alias Sanbase.Influxdb.Measurement

  import Plug.Conn

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

    Store.drop_measurement("TEST_BTC")
    Store.drop_measurement("TEST_USD")

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
    Store.drop_measurement("SAN_USD")

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
    now = DateTime.utc_now()
    two_days_ago = Sanbase.DateTimeUtils.seconds_ago(2 * 60 * 60 * 24)

    query = """
    {
      historyPrice(ticker: "TEST", from: "#{two_days_ago}", to: "#{now}", interval: "10w") {
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
    assert history_price["volume"] == "500"
    assert history_price["marketcap"] == "650"
  end

  test "too complex queries are denied", context do
    now = DateTime.utc_now()
    years_ago = Sanbase.DateTimeUtils.days_ago(10 * 365)

    query = """
    {
      historyPrice(ticker: "TEST", from: "#{years_ago}", to: "#{now}", interval: "5m"){
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
    yesterday = Sanbase.DateTimeUtils.days_ago(1)

    query = """
    {
      historyPrice(ticker: "TEST", from: "#{yesterday}"){
        priceUsd
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "historyPrice"))

    history_price = json_response(result, 200)["data"]["historyPrice"]
    assert Enum.count(history_price) == 2
    assert Enum.at(history_price, 0)["priceUsd"] == "20"
    assert Enum.at(history_price, 1)["priceUsd"] == "22"
  end

  test "complexity is 0 with basic authentication", context do
    username =
      Application.fetch_env!(:sanbase, SanbaseWeb.Graphql.ContextPlug)
      |> Keyword.get(:basic_auth_username)

    password =
      Application.fetch_env!(:sanbase, SanbaseWeb.Graphql.ContextPlug)
      |> Keyword.get(:basic_auth_password)

    basic_auth = Base.encode64(username <> ":" <> password)

    now = DateTime.utc_now()
    years_ago = Sanbase.DateTimeUtils.days_ago(10 * 365)

    query = """
    {
      historyPrice(ticker: "TEST", from: "#{years_ago}", to: "#{now}", interval: "5m"){
        priceUsd
        priceBtc
        datetime
        volume
      }
    }
    """

    result =
      context.conn
      |> put_req_header("authorization", "Basic " <> basic_auth)
      |> post("/graphql", query_skeleton(query, "historyPrice"))

    assert json_response(result, 200)["data"] != nil
  end

  test "fetch all available prices", context do
    now = DateTime.utc_now() |> DateTime.to_unix(:nanoseconds)

    Store.import([
      # older
      %Measurement{
        timestamp: now,
        fields: %{price: 1, volume: 5, marketcap: 500},
        name: "XYZ_BTC"
      },
      %Measurement{
        timestamp: now,
        fields: %{price: 20, volume: 200, marketcap: 500},
        name: "XYZ_USD"
      }
    ])

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
end