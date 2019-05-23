defmodule SanbaseWeb.Graphql.PricesApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Plug.Conn
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  alias Sanbase.Prices.Store
  alias Sanbase.Influxdb.Measurement

  setup do
    Store.create_db()

    slug1 = "test122"
    ticker1 = "TEST"
    slug2 = "xyz122"
    ticker2 = "XYZ"
    total_market_ticker_cmc_id = "TOTAL_MARKET_total-market"

    ticker_cmc_id1 = ticker1 <> "_" <> slug1
    ticker_cmc_id2 = ticker2 <> "_" <> slug2

    infr_eth = insert(:infrastructure_eth)

    insert(:project,
      name: "Test project",
      coinmarketcap_id: slug1,
      ticker: ticker1,
      infrastructure: infr_eth,
      main_contract_address: "0x123"
    )

    insert(:project,
      name: "XYZ project",
      coinmarketcap_id: slug2,
      ticker: ticker2,
      infrastructure: infr_eth,
      main_contract_address: "0x234"
    )

    Store.drop_measurement(ticker_cmc_id1)
    Store.drop_measurement(ticker_cmc_id2)
    Store.drop_measurement(total_market_ticker_cmc_id)

    datetime1 = DateTime.from_naive!(~N[2017-05-13 21:45:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-14 21:45:00], "Etc/UTC")
    datetime3 = DateTime.from_naive!(~N[2017-05-15 21:45:00], "Etc/UTC")
    years_ago = DateTime.from_naive!(~N[2007-01-01 21:45:00], "Etc/UTC")

    Store.import([
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanosecond),
        fields: %{price_usd: 20, price_btc: 1000, volume_usd: 200, marketcap_usd: 500},
        name: ticker_cmc_id1
      },
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanosecond),
        fields: %{price_usd: 22, price_btc: 1200, volume_usd: 300, marketcap_usd: 800},
        name: ticker_cmc_id1
      },
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanosecond),
        fields: %{price_usd: 20, price_btc: 1, volume_usd: 5, marketcap_usd: 500},
        name: ticker_cmc_id2
      },
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanosecond),
        fields: %{volume_usd: 1200, marketcap_usd: 1500},
        name: total_market_ticker_cmc_id
      },
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanosecond),
        fields: %{volume_usd: 1300, marketcap_usd: 1800},
        name: total_market_ticker_cmc_id
      }
    ])

    [
      datetime1: datetime1,
      datetime2: datetime2,
      datetime3: datetime3,
      years_ago: years_ago,
      slug1: slug1,
      slug2: slug2,
      total_market_slug: "TOTAL_MARKET",
      total_market_measurement: total_market_ticker_cmc_id
    ]
  end

  test "no information is available for a non existing slug", context do
    Store.drop_measurement("SAN_USD")

    query =
      history_price_query("non_existing 1237819", context.datetime1, context.datetime2, "1h")

    result = context.conn |> execute_query(query, "historyPrice")

    assert result == nil
  end

  test "data aggregation for automatically calculated intervals", context do
    query = """
    {
      historyPrice(
        slug: "#{context.slug1}",
        from: "#{context.datetime1}",
        to: "#{context.datetime3}") {
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
      historyPrice(
        slug: "#{context.slug1}",
        from: "#{context.datetime1}",
        to: "#{context.datetime3}",
        interval: "2d") {
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
      |> json_response(200)

    error = result["errors"] |> List.first()
    assert String.contains?(error["message"], "too complex")
  end

  test "complexity is 0 with basic authentication", context do
    query = history_price_query(context.slug1, context.years_ago, context.datetime1, "5m")

    result =
      context.conn
      |> put_req_header("authorization", "Basic " <> basic_auth())
      |> post("/graphql", query_skeleton(query, "historyPrice"))

    assert json_response(result, 200)["data"] != nil
  end

  test "no information is available for total marketcap", context do
    Store.drop_measurement(context.total_market_measurement)

    query =
      history_price_query(context.total_market_slug, context.datetime1, context.datetime2, "1h")

    result = context.conn |> execute_query(query, "historyPrice")

    assert result == []
  end

  test "historyPrice with TOTAL_ERC20 slug", context do
    query = history_price_query("TOTAL_ERC20", context.datetime2, context.datetime3, "1d")

    result = context.conn |> execute_query(query, "historyPrice")

    assert result == [
             %{
               "datetime" => "2017-05-14T00:00:00Z",
               "marketcap" => 500,
               "priceBtc" => nil,
               "priceUsd" => nil,
               "volume" => 200
             },
             %{
               "datetime" => "2017-05-15T00:00:00Z",
               "marketcap" => 1300,
               "priceBtc" => nil,
               "priceUsd" => nil,
               "volume" => 305
             }
           ]
  end

  test "the whole response is as it's expected to be", context do
    query = history_price_query(context.slug1, context.datetime1, context.datetime3, "6h")

    result = context.conn |> execute_query(query, "historyPrice")

    assert result == [
             %{
               "datetime" => "2017-05-14T18:00:00Z",
               "marketcap" => 500,
               "priceBtc" => 1000,
               "priceUsd" => 20,
               "volume" => 200
             },
             %{
               "datetime" => "2017-05-15T18:00:00Z",
               "marketcap" => 800,
               "priceBtc" => 1200,
               "priceUsd" => 22,
               "volume" => 300
             }
           ]
  end

  test "project group stats with existing slugs returns correct stats", context do
    slugs = [context.slug1, context.slug2]
    query = project_group_stats_query(slugs, context.datetime1, context.datetime3)
    result = execute_query(context.conn, query, "projectsListStats")

    assert [
             %{
               "volume" => 300,
               "marketcap" => 800,
               "marketcapPercent" => Float.round(800 / 1300, 5),
               "slug" => context.slug1
             },
             %{
               "volume" => 5,
               "marketcap" => 500,
               "marketcapPercent" => Float.round(500 / 1300, 5),
               "slug" => context.slug2
             }
           ] == result
  end

  test "project group stats with non existing slugs return no data", context do
    query = project_group_stats_query(["non-existing"], context.datetime1, context.datetime3)
    result = execute_query(context.conn, query, "projectsListStats")
    assert result == nil
  end

  test "project group stats with existing and non existing slugs ignores latter", context do
    query =
      project_group_stats_query(
        [context.slug1, "non-existing"],
        context.datetime1,
        context.datetime3
      )

    result = execute_query(context.conn, query, "projectsListStats")

    assert [
             %{
               "volume" => 300,
               "marketcap" => 800,
               "marketcapPercent" => 1.0000,
               "slug" => context.slug1
             }
           ] == result
  end

  defp project_group_stats_query(slugs, from, to) do
    slugs_str = slugs |> Enum.map(fn slug -> ~s|"#{slug}"| end) |> Enum.join(",")

    """
    {
      projectsListStats(
        slugs: [#{slugs_str}],
        from: "#{from}",
        to: "#{to}"
      ) {
        volume,
        marketcap,
        slug,
        marketcapPercent
      }
    }
    """
  end

  defp history_price_query(slug, from, to, interval) do
    """
    {
      historyPrice(
        slug: "#{slug}",
        from: "#{from}",
        to: "#{to}"
        interval: "#{interval}"){
          datetime
          volume
          marketcap
          priceUsd
          priceBtc
      }
    }
    """
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
