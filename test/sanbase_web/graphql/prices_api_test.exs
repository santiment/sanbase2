defmodule SanbaseWeb.Graphql.PricesApiTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Prices.Store
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Model.Project
  alias Sanbase.Repo

  import Plug.Conn
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    Store.create_db()

    slug1 = "tester"

    %Project{}
    |> Project.changeset(%{name: "Project1", ticker: "TEST", coinmarketcap_id: slug1})
    |> Repo.insert!()

    slug2 = "tester2"

    %Project{}
    |> Project.changeset(%{name: "Project2", ticker: "XYZ", coinmarketcap_id: slug2})
    |> Repo.insert!()

    Store.drop_measurement("TEST_BTC")
    Store.drop_measurement("TEST_USD")
    Store.drop_measurement("XYZ_USD")
    Store.drop_measurement("XYZ_BTC")
    Store.drop_measurement("TOTAL_MARKET_USD")

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
      },
      # older
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: 1200, marketcap: 1500},
        name: "TOTAL_MARKET_USD"
      },
      # newer
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanoseconds),
        fields: %{volume: 1300, marketcap: 1800},
        name: "TOTAL_MARKET_USD"
      }
    ])

    [
      datetime1: datetime1,
      datetime2: datetime2,
      datetime3: datetime3,
      years_ago: years_ago,
      slug1: slug1,
      slug2: slug2
    ]
  end

  test "no information is available for a non existing slug", context do
    Store.drop_measurement("SAN_USD")

    query = """
    {
      historyPrice(
        slug: "non_existing 1237819",
        from: "#{context.datetime1}",
        to: "#{context.datetime2}",
        interval: "1h") {
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

  test "data aggregation for automatically calculated intervals", context do
    query = """
    {
      historyPrice(slug: "#{context.slug1}", from: "#{context.datetime1}", to: "#{
      context.datetime3
    }") {
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
    assert Enum.count(history_price) == 2

    [history_price | _] = history_price
    assert history_price["priceUsd"] == 20
    assert history_price["priceBtc"] == 1000
    assert history_price["volume"] == 200
    assert history_price["marketcap"] == 500
  end

  test "data aggregation for larger intervals", context do
    query = """
    {
      historyPrice(slug: "#{context.slug1}", from: "#{context.datetime1}", to: "#{
      context.datetime3
    }", interval: "2d") {
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
    assert history_price["priceUsd"] == 21
    assert history_price["priceBtc"] == 1100
    assert history_price["volume"] == 300
    assert history_price["marketcap"] == 650
  end

  test "too complex queries are denied", context do
    query = """
    {
      historyPrice(
        slug: "#{context.slug1}",
        from: "#{context.years_ago}",
        to: "#{context.datetime1}",
        interval: "5m"){
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
      historyPrice(
        slug: "#{context.slug1}",
        from: "#{context.datetime1}",
        interval: "1h"){
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
    assert Enum.at(history_price, 0)["priceUsd"] == 20
    assert Enum.at(history_price, 1)["priceUsd"] == 22
  end

  test "complexity is 0 with basic authentication", context do
    query = """
    {
      historyPrice(
        slug: "#{context.slug1}",
        from: "#{context.years_ago}",
        to: "#{context.datetime1}",
        interval: "5m"){
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

  test "no information is available for total marketcap", context do
    Store.drop_measurement("TOTAL_MARKET_USD")

    query = """
    {
      historyPrice(
        slug: "TOTAL_MARKET",
        from: "#{context.datetime1}",
        to: "#{context.datetime2}",
        interval: "1h") {
          datetime
          volume
          marketcap
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "historyPrice"))

    assert json_response(result, 200)["data"]["historyPrice"] == []
  end

  test "default arguments for total marketcap are correctly set", context do
    query = """
    {
      historyPrice(
        slug: "TOTAL_MARKET",
        from: "#{context.datetime1}",
        interval: "1h"){
        datetime
        volume
        marketcap
      }
    }
    """

    result =
      context.conn
      |> put_req_header("authorization", "Basic " <> basic_auth())
      |> post("/graphql", query_skeleton(query, "historyPrice"))

    history_price = json_response(result, 200)["data"]["historyPrice"]
    assert Enum.count(history_price) == 2
    assert Enum.at(history_price, 0)["volume"] == 1200
    assert Enum.at(history_price, 0)["marketcap"] == 1500
    assert Enum.at(history_price, 1)["volume"] == 1300
    assert Enum.at(history_price, 1)["marketcap"] == 1800
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
