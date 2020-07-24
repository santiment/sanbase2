defmodule SanbaseWeb.Graphql.ExchangesTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers

  setup_with_mocks([
    {Sanbase.Clickhouse.ExchangeAddress, [:passthrough],
     exchange_addresses: fn _ ->
       {:ok,
        [
          %{address: "0x234", name: "Binance", is_dex: false},
          %{address: "0x789", name: "Binance", is_dex: false},
          %{address: "0x567", name: "Bitfinex", is_dex: false}
        ]}
     end},
    {
      Sanbase.Clickhouse.ExchangeAddress,
      [:passthrough],
      exchange_names: fn _, _ -> {:ok, ["Binance", "Bitfinex"]} end
    }
  ]) do
    []
  end

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

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
    query = ~s/{ allExchanges(slug: "ethereum") }/

    response =
      context.conn
      |> post("/graphql", query_skeleton(query, "allExchanges"))

    exchanges =
      json_response(response, 200)
      |> get_in(["data", "allExchanges"])

    assert Enum.sort(exchanges) == Enum.sort(["Binance", "Bitfinex"])
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
