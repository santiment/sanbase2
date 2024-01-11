defmodule Sanbase.ExternalServices.Coinmarketcap.PricePointTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.ExternalServices.Coinmarketcap.PricePoint
  alias Sanbase.Project

  @total_market_slug "TOTAL_MARKET"

  setup do
    ts =
      DateTime.from_naive!(~N[2018-05-13 21:45:00], "Etc/UTC")
      |> DateTime.to_unix(:nanosecond)

    price_point = %PricePoint{
      price_btc: nil,
      price_usd: nil,
      marketcap_usd: 400,
      volume_usd: 500,
      datetime: DateTime.from_unix!(ts, :nanosecond)
    }

    price_point_with_prices = %PricePoint{
      price_btc: 3.136261180345569e-5,
      price_usd: 0.292856,
      marketcap_usd: 400,
      volume_usd: 500,
      datetime: DateTime.from_unix!(ts, :nanosecond)
    }

    project = %Project{
      ticker: "SAN",
      slug: "santiment"
    }

    %{
      price_point: price_point,
      price_point_with_prices: price_point_with_prices,
      project: project
    }
  end

  describe "#json_kv_tuple" do
    test "convert price point with prices to tuple of json values", context do
      {key, value} =
        PricePoint.json_kv_tuple(context.price_point_with_prices, context.project.slug)

      assert key == "coinmarketcap_santiment_2018-05-13T21:45:00.000000Z"

      assert value ==
               "{\"timestamp\":1526247900,\"source\":\"coinmarketcap\",\"slug\":\"santiment\",\"price_usd\":0.292856,\"price_btc\":3.136261180345569e-5,\"volume_usd\":500,\"marketcap_usd\":400}"
    end

    test "convert price point without prices to tuple of json values", context do
      {key, value} = PricePoint.json_kv_tuple(context.price_point, @total_market_slug)
      assert key == "coinmarketcap_TOTAL_MARKET_2018-05-13T21:45:00.000000Z"

      assert value ==
               "{\"timestamp\":1526247900,\"source\":\"coinmarketcap\",\"slug\":\"TOTAL_MARKET\",\"price_usd\":null,\"price_btc\":null,\"volume_usd\":500,\"marketcap_usd\":400}"
    end
  end
end
