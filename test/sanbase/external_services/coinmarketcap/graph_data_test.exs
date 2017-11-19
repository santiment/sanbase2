defmodule Sanbase.ExternalServices.Coinmarketcap.GraphDataTest do
  use ExUnit.Case

  alias Sanbase.ExternalServices.Coinmarketcap.{GraphData, PricePoint}

  test "fetching the first price datetime of a token" do
    Tesla.Mock.mock fn
      %{method: :get, url: "https://graphs.coinmarketcap.com/currencies/santiment/"} ->
        %Tesla.Env{status: 200, body: File.read!(Path.join(__DIR__, "btc_graph_data.json"))}
    end

    assert GraphData.fetch_first_price_datetime("santiment") == DateTime.from_unix!(1507991665000, :millisecond)
  end

  test "fetching prices of a token" do
    Tesla.Mock.mock fn
      %{method: :get, url: "https://graphs.coinmarketcap.com/currencies/santiment/1507991665000/1508078065000/"} ->
        %Tesla.Env{status: 200, body: File.read!(Path.join(__DIR__, "btc_graph_data.json"))}
    end

    from_datetime = DateTime.from_unix!(1507991665000, :millisecond)
    to_datetime = DateTime.from_unix!(1508078065000, :millisecond)

    GraphData.fetch_prices("santiment", from_datetime, to_datetime)
    |> Stream.take(1)
    |> Enum.map(fn %PricePoint{datetime: datetime, price_usd: price_usd} ->
      assert datetime == from_datetime
      assert price_usd == 5704.29
    end)
  end
end
