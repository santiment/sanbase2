defmodule SanbaseWeb.Graphql.HyperliquidBboApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Hyperliquid.Bbo.BboPrices

  setup do
    %{
      slug: "bitcoin",
      from: ~U[2026-05-07 00:00:00Z],
      to: ~U[2026-05-07 00:05:00Z],
      t1: ~U[2026-05-07 00:00:00Z],
      t2: ~U[2026-05-07 00:01:00Z]
    }
  end

  test "returns BBO points with computed mid and weighted_mid", ctx do
    %{conn: conn, slug: slug, from: from, to: to, t1: t1, t2: t2} = ctx

    data = [
      %{
        datetime: t1,
        bid_price: 100.0,
        bid_volume: 2.0,
        ask_price: 102.0,
        ask_volume: 4.0,
        mid_price: 101.0,
        weighted_mid_price: 604.0 / 6.0
      },
      %{
        datetime: t2,
        bid_price: nil,
        bid_volume: nil,
        ask_price: 200.0,
        ask_volume: 1.0,
        mid_price: nil,
        weighted_mid_price: nil
      }
    ]

    Sanbase.Mock.prepare_mock2(&BboPrices.timeseries_data/4, {:ok, data})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        run_query(conn, slug, from, to, "1m")
        |> get_in(["data", "hyperliquidBboPrices"])

      assert result == [
               %{
                 "datetime" => DateTime.to_iso8601(t1),
                 "bidPrice" => 100.0,
                 "bidVolume" => 2.0,
                 "askPrice" => 102.0,
                 "askVolume" => 4.0,
                 "midPrice" => 101.0,
                 "weightedMidPrice" => 604.0 / 6.0
               },
               %{
                 "datetime" => DateTime.to_iso8601(t2),
                 "bidPrice" => nil,
                 "bidVolume" => nil,
                 "askPrice" => 200.0,
                 "askVolume" => 1.0,
                 "midPrice" => nil,
                 "weightedMidPrice" => nil
               }
             ]
    end)
  end

  test "accepts cachingParams to disable caching", ctx do
    %{conn: conn, slug: slug, from: from, to: to, t1: t1} = ctx

    data = [
      %{
        datetime: t1,
        bid_price: 100.0,
        bid_volume: 1.0,
        ask_price: 101.0,
        ask_volume: 1.0,
        mid_price: 100.5,
        weighted_mid_price: 100.5
      }
    ]

    Sanbase.Mock.prepare_mock2(&BboPrices.timeseries_data/4, {:ok, data})
    |> Sanbase.Mock.run_with_mocks(fn ->
      caching = "cachingParams: { baseTtl: 1, maxTtlOffset: 1 }"
      result = run_query(conn, slug, from, to, "1m", caching)

      assert result["errors"] == nil
      assert length(result["data"]["hyperliquidBboPrices"]) == 1
    end)
  end

  test "interval is required", ctx do
    %{conn: conn, slug: slug, from: from, to: to} = ctx

    query = """
    {
      hyperliquidBboPrices(
        slug: "#{slug}"
        from: "#{from}"
        to: "#{to}"
      ) {
        datetime
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "hyperliquidBboPrices"))
      |> json_response(200)

    assert result["errors"] != nil
  end

  defp run_query(conn, slug, from, to, interval, extra_args \\ "") do
    extra = if extra_args == "", do: "", else: "\n      #{extra_args}"

    query = """
    {
      hyperliquidBboPrices(
        slug: "#{slug}"
        from: "#{from}"
        to: "#{to}"
        interval: "#{interval}"#{extra}
      ) {
        datetime
        bidPrice
        bidVolume
        askPrice
        askVolume
        midPrice
        weightedMidPrice
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query, "hyperliquidBboPrices"))
    |> json_response(200)
  end
end
