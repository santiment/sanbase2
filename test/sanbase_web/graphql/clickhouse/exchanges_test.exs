defmodule SanbaseWeb.Graphql.ExchangesTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.DateTimeUtils, only: [from_iso8601_to_unix!: 1]

  setup do
    infr = insert(:infrastructure, %{code: "ETH"})

    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    conn = setup_jwt_auth(build_conn(), user)

    insert(:exchange_address, %{address: "0x234", name: "Binance", infrastructure_id: infr.id})
    insert(:exchange_address, %{address: "0x567", name: "Bitfinex", infrastructure_id: infr.id})
    insert(:exchange_address, %{address: "0x789", name: "Binance", infrastructure_id: infr.id})

    insert(:exchange_market_pair_mappings, %{
      exchange: "Bitfinex",
      market_pair: "SAN/USD",
      from_slug: "santiment",
      to_slug: "usd",
      source: "coinmarketcap",
      from_ticker: "SAN",
      to_ticker: "USD"
    })

    [
      exchange: "Binance",
      conn: conn,
      from: Timex.shift(Timex.now(), days: -10),
      to: Timex.now()
    ]
  end

  test "test all exchanges", context do
    query = "{ allExchanges }"

    response =
      context.conn
      |> post("/graphql", query_skeleton(query, "allExchanges"))

    exchanges = json_response(response, 200)["data"]["allExchanges"]
    assert Enum.sort(exchanges) == Enum.sort(["Binance", "Bitfinex"])
  end

  test "test fetching volume for exchange", context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [from_iso8601_to_unix!("2017-05-13T00:00:00Z"), 2000, 1000],
             [from_iso8601_to_unix!("2017-05-15T00:00:00Z"), 1800, 1300],
             [from_iso8601_to_unix!("2017-05-18T00:00:00Z"), 1000, 1100]
           ]
         }}
      end do
      query =
        exchange_volume_query(
          context.exchange,
          context.from,
          context.to
        )

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "exchangeVolume"))
        |> json_response(200)

      exchanges = result["data"]["exchangeVolume"]

      assert exchanges == [
               %{
                 "datetime" => "2017-05-13T00:00:00Z",
                 "exchange_inflow" => 2000,
                 "exchange_outflow" => 1000
               },
               %{
                 "datetime" => "2017-05-15T00:00:00Z",
                 "exchange_inflow" => 1800,
                 "exchange_outflow" => 1300
               },
               %{
                 "datetime" => "2017-05-18T00:00:00Z",
                 "exchange_inflow" => 1000,
                 "exchange_outflow" => 1100
               }
             ]
    end
  end

  describe "#exchangeMarketPairToSlugs" do
    test "returns the proper slugs" do
      query = exchange_market_pair_to_slugs("Bitfinex", "SAN/USD")
      result = execute_query(build_conn(), query, "exchangeMarketPairToSlugs")
      assert result == %{"fromSlug" => "santiment", "toSlug" => "usd"}
    end

    test "returns nulls" do
      query = exchange_market_pair_to_slugs("Non-existing", "SAN/USD")
      result = execute_query(build_conn(), query, "exchangeMarketPairToSlugs")
      assert result == %{"fromSlug" => nil, "toSlug" => nil}
    end
  end

  describe "#slugsToExchangeMarketPair" do
    test "returns the proper slugs" do
      query = slugs_to_exchange_market_pair_query("Bitfinex", "santiment", "usd")
      result = execute_query(build_conn(), query, "slugsToExchangeMarketPair")

      assert result == %{
               "marketPair" => "SAN/USD",
               "fromTicker" => "SAN",
               "toTicker" => "USD"
             }
    end

    test "returns nulls" do
      query = slugs_to_exchange_market_pair_query("Non-existing", "santiment", "usd")
      result = execute_query(build_conn(), query, "slugsToExchangeMarketPair")
      assert result == %{"fromTicker" => nil, "marketPair" => nil, "toTicker" => nil}
    end
  end

  defp exchange_volume_query(exchange, from, to) do
    """
      {
        exchangeVolume(
            exchange: "#{exchange}",
            from: "#{from}",
            to: "#{to}",
        ){
            datetime,
            exchange_inflow,
            exchange_outflow
        }
      }
    """
  end

  defp exchange_market_pair_to_slugs(exchange, ticker_pair) do
    """
    {
      exchangeMarketPairToSlugs(exchange:"#{exchange}", tickerPair:"#{ticker_pair}") {
        fromSlug
        toSlug
      }
    }
    """
  end

  defp slugs_to_exchange_market_pair_query(exchange, from_slug, to_slug) do
    """
    {
      slugsToExchangeMarketPair(exchange:"#{exchange}", fromSlug:"#{from_slug}", toSlug:"#{
      to_slug
    }") {
        marketPair
        fromTicker
        toTicker
      }
    }
    """
  end
end
